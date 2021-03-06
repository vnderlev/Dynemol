module ElHl_Chebyshev_m

    use MPI
    use type_m             , g_time => f_time  
    use blas95
    use lapack95
    use constants_m
    use ifport
    use MPI_definitions_m  , only : master , EnvCrew ,  myCheby ,   &       
                                    ChebyComm , ChebyCrew ,         &  
                                    ForceComm , ForceCrew ,         &
                                    KernelComm , ChebyKernelComm   
    use parameters_m       , only : t_i , frame_step , Coulomb_ ,   &
                                    EnvField_ , n_part, driver ,    &
                                    QMMM, CT_dump_step , HFP_Forces
    use Structure_Builder  , only : Unit_Cell 
    use Overlap_Builder    , only : Overlap_Matrix
    use FMO_m              , only : FMO_analysis , eh_tag    
    use Data_Output        , only : Populations 
    use Hamiltonians       , only : X_ij , even_more_extended_Huckel
    use Taylor_m           , only : Propagation, dump_Qdyn
    use Matrix_Math

    public  :: ElHl_Chebyshev , preprocess_ElHl_Chebyshev , Build_Huckel , QuasiParticleEnergies , preprocess_from_restart

    private

! module parameters ...
    integer       , parameter   :: order       = 25
    real*8        , parameter   :: error       = 1.0d-12
    real*8        , parameter   :: norm_error  = 1.0d-12

! module variables ...
    logical       , save        :: first_call_ = .true.
    real*8        , save        :: save_tau(2)
    real*8, target, allocatable :: h0(:,:)
    real*8        , allocatable :: S_matrix(:,:)
    complex*16    , allocatable :: Psi_t_bra(:,:) , Psi_t_ket(:,:)

    interface preprocess_ElHl_Chebyshev
        module procedure preprocess_ElHl_Chebyshev
        module procedure preprocess_from_restart
    end interface

contains
!
!
!
!==========================================================================================================
 subroutine preprocess_ElHl_Chebyshev( system , basis , AO_bra , AO_ket , Dual_bra , Dual_ket , QDyn , it )
! used for normal start (see interface) ...
!==========================================================================================================
implicit none
type(structure) , intent(inout) :: system
type(STO_basis) , intent(inout) :: basis(:)
complex*16      , intent(out)   :: AO_bra(:,:)
complex*16      , intent(out)   :: AO_ket(:,:)
complex*16      , intent(out)   :: DUAL_bra(:,:) 
complex*16      , intent(out)   :: DUAL_ket(:,:) 
type(g_time)    , intent(inout) :: QDyn
integer         , intent(in)    :: it

!local variables ...
integer                         :: N , err 
integer                         :: mpi_D_R = mpi_double_precision
type(R_eigen)                   :: AO

! MUST compute S_matrix before FMO analysis ...
CALL Overlap_Matrix( system , basis , S_matrix )

N = size(basis)

allocate( h0(N,N) , source = D_zero )

!------------------------------------------------------------------------
If( master .OR. EnvCrew ) then 

   If( EnvField_ ) then
      ! EnCrew stay in even_more_extended_Huckel ...
      h0(:,:) = even_more_extended_Huckel( system , basis , S_matrix )
   Else
      h0(:,:) = Build_Huckel( basis , S_matrix )
   end If

   CALL MPI_BCAST( h0 , N*N , mpi_D_R , 0 , ForceComm , err )
   CALL MPI_BCAST( h0 , N*N , mpi_D_R , 0 , ChebyComm , err )

End If

If( ForceCrew ) then
   ! After instantiating S_matrix AND h0, ForceCrew leave to EhrenfestForce ...
   CALL MPI_BCAST( h0 , N*N , mpi_D_R , 0 , ForceComm , err )
   return
End If

! Another ChebyCrew  mate ...
If( myCheby == 1 ) CALL MPI_BCAST( h0 , N*N , mpi_D_R , 0 , ChebyComm , err )
!------------------------------------------------------------------------

!========================================================================
! prepare electron state ...
  CALL FMO_analysis( system , basis, AO=AO , instance="E" )

  AO_bra(:,1) = dcmplx(AO%L(:,1))
  AO_ket(:,1) = dcmplx(AO%R(:,1))
  deallocate( AO%L , AO%R )

! prepare hole state ...
  CALL FMO_analysis( system , basis, AO=AO , instance="H" )
  
  AO_bra(:,2) = dcmplx(AO%L(:,2))
  AO_ket(:,2) = dcmplx(AO%R(:,2))
  deallocate( AO%L , AO%R  )
!========================================================================

!==============================================
! prepare DUAL basis for local properties ...
! DUAL_bra = (C*)^T    ;    DUAL_ket = S*C ...
  DUAL_bra = AO_bra
  call op_x_ket( DUAL_ket, S_matrix , AO_ket )
!==============================================

!==============================================
! vector states to be propagated ...
! Psi_bra = C^T*S       ;      Psi_ket = C ...
  allocate( Psi_t_bra(N,n_part) )
  allocate( Psi_t_ket(N,n_part) )
  call bra_x_op( Psi_t_bra, AO_bra , S_matrix ) 
  Psi_t_ket = AO_ket
!==============================================

!==============================================
! preprocess stuff for EhrenfestForce ...
  CALL QuasiParticleEnergies(AO_bra, AO_ket, H0)
!==============================================

! save populations(time=t_i) ...
QDyn%dyn(it,:,:) = Populations( QDyn%fragments , basis , DUAL_bra , DUAL_ket , t_i )
if (master) CALL dump_Qdyn( Qdyn , it )

! leaving S_matrix allocated

end subroutine preprocess_ElHl_Chebyshev
!
!
!
!=============================================================================================================
 subroutine ElHl_Chebyshev( system , basis , AO_bra , AO_ket , Dual_bra , Dual_ket , QDyn , t , delta_t , it )
!=============================================================================================================
implicit none
type(structure)  , intent(in)    :: system
type(STO_basis)  , intent(in)    :: basis(:)
complex*16       , intent(inout) :: AO_bra(:,:)
complex*16       , intent(inout) :: AO_ket(:,:)
complex*16       , intent(inout) :: Dual_bra(:,:)
complex*16       , intent(inout) :: Dual_ket(:,:)
type(g_time)     , intent(inout) :: QDyn
real*8           , intent(inout) :: t
real*8           , intent(in)    :: delta_t
integer          , intent(in)    :: it

! local variables...
integer :: N , err , mpi_status(mpi_status_size)
integer :: req1 , req2 , it_sync
integer :: mpi_D_R = mpi_double_precision
integer :: mpi_D_C = mpi_double_complex
real*8  :: t_init , t_max , tau_max , tau(2) , t_stuff(2)

real*8  , pointer :: h(:,:)
real*8  , save , allocatable :: H_prime(:,:) , S_inv(:,:)

N = size(basis)

t_init = t
! max time inside slice ...
t_max = delta_t*frame_step*(it-1)
! constants of evolution ...
tau_max = delta_t / h_bar

If( master ) then ! <== Electron wpckt Dynamics ...

    if(first_call_) allocate( H(N,N) , H_prime(N,N) , S_inv(N,N) )

    ! trying to adapt time step for efficient propagation ...
    tau(1) = merge( tau_max , save_tau(1) * 1.15d0 , first_call_ )
    ! but tau should be never bigger than tau_max ...
    tau(1) = merge( tau_max , tau(1) , tau(1) > tau_max )

    t_stuff = [ t_init , t_max ]
    CALL MPI_ISend( t_stuff , 2 , mpi_D_R , 1 , 0 , ChebyComm , req1 , err )
    CALL MPI_Request_Free( req1 , err )

    ! compute S  and H0 ...
    CALL Overlap_Matrix( system , basis , S_matrix )

    If( Envfield_ ) then
        it_sync = it-1  ! <== for synchronizing EnvSetUp call therein ...
        h0(:,:) = even_more_extended_Huckel( system , basis , S_matrix , it_sync )
    else
        h0(:,:) = Build_Huckel( basis , S_matrix )
    end If

    h => h0

    ! S_matrix content is destroyed and S_inv is returned
    CALL syInvert( S_matrix, return_full )   
    S_inv = S_matrix

    ! compute H' = S_inv * H ...
    CALL syMultiply( S_inv , h , H_prime )

    CALL MPI_BCAST( QMMM , 1 , mpi_logical , 0 , ChebyComm , err )
    If( QMMM ) then
         ! for using in Ehrenfest; Chebyshev also delivers data to Ehrenfest ...
         CALL MPI_BCAST( AO_bra , 2*N , mpi_D_C , 0 , KernelComm , err )
         CALL MPI_BCAST( AO_ket , 2*N , mpi_D_C , 0 , KernelComm , err )

         CALL MPI_IBCAST( H_prime , N*N , mpi_D_R , 0 , ChebyKernelComm , req2 , err )
    else
         ! otherwise, only Hole Dynamics get it ...
         CALL MPI_IBCAST( H_prime , N*N , mpi_D_R , 0 , ChebyComm , req2 , err )
    end If

    !===================
    ! Electron Dynamics
    !===================
    ! proceed evolution of ELECTRON wapacket with best tau ...
    CALL Propagation( N, H_prime, Psi_t_bra(:,1), Psi_t_ket(:,1), t_init, t_max, tau(1), save_tau(1) )

else If( myCheby == 1 ) then  ! <== Hole wpckt Dynamics ...

    do  ! <== myCheby = 1 dwells in here Forever ...

         CALL MPI_Recv( t_stuff , 2 , mpi_D_R , 0 , mpi_any_tag , ChebyComm , mpi_status , err )
         CALL MPI_BCAST( QMMM , 1 , mpi_logical , 0 , ChebyComm , err )

         tau(2) = merge( tau_max , save_tau(2) * 1.15d0 , first_call_ )
         tau(2) = merge( tau_max , tau(2) , tau(2) > tau_max )

         Allocate( H_prime(N,N) )

         If( QMMM ) then
              CALL MPI_IBCAST( H_prime , N*N , mpi_D_R , 0 , ChebyKernelComm , req2 , err )
         else
              CALL MPI_IBCAST( H_prime , N*N , mpi_D_R , 0 , ChebyComm , req2 , err )
         end If
         CALL MPI_Wait( req2 , mpi_status , err ) 

         !===================
         !  Hole   Dynamics
         !===================
         ! proceed evolution of HOLE wapacket with best tau ...
         CALL Propagation( N , H_prime , Psi_t_bra(:,2) , Psi_t_ket(:,2) , t_stuff(1) , t_stuff(2) , tau(2) , save_tau(2) )

         CALL MPI_Send( Psi_t_bra(:,2) , N , mpi_D_C , 0 , 0 , ChebyComm , err )
         CALL MPI_Send( Psi_t_ket(:,2) , N , mpi_D_C , 0 , 0 , ChebyComm , err )

         deallocate( H_prime ) 

    end do  !<== Return to Forever ...

end If

CALL MPI_Recv( Psi_t_bra(:,2) , N , mpi_D_C , 1 , mpi_any_tag , ChebyComm , mpi_status , err )
CALL MPI_Recv( Psi_t_ket(:,2) , N , mpi_D_C , 1 , mpi_any_tag , ChebyComm , mpi_status , err )

t = t_init + (delta_t*frame_step)

! prepare DUAL basis for local properties ...
DUAL_bra = dconjg(Psi_t_ket)
DUAL_ket = Psi_t_bra

! prepare Slater basis for FORCE properties ...
call op_x_ket( AO_bra, S_inv, Psi_t_bra )
AO_bra = dconjg(AO_bra) 
AO_ket = Psi_t_ket

CALL QuasiParticleEnergies( AO_bra , AO_ket , H )

! save populations(time) ...
QDyn%dyn(it,:,:) = Populations( QDyn%fragments , basis , DUAL_bra , DUAL_ket , t )

if( mod(it,CT_dump_step) == 0 ) CALL dump_Qdyn( Qdyn , it )

nullify( h )

first_call_ = .false.

include 'formats.h'

end subroutine ElHl_Chebyshev
!
!
!
!===================================================
 function Build_Huckel( basis , S_matrix ) result(h)
!===================================================
implicit none
type(STO_basis) , intent(in)    :: basis(:)
real*8          , intent(in)    :: S_matrix(:,:)

! local variables ... 
integer               :: i , j , N
real*8  , allocatable :: h(:,:)

!----------------------------------------------------------
!      building  the  HUCKEL  HAMILTONIAN
!----------------------------------------------------------

N = size(basis)
ALLOCATE( h(N,N) , source = D_zero )

do j = 1 , N
  do i = 1 , j

        h(i,j) = X_ij( i , j , basis ) * S_matrix(i,j)

        h(j,i) = h(i,j)

    end do
end do

end function Build_Huckel
!
!
!
!
!=======================================================
 subroutine QuasiParticleEnergies( AO_bra , AO_ket , H )
!=======================================================
implicit none
complex*16 , intent(in) :: AO_bra(:,:)
complex*16 , intent(in) :: AO_ket(:,:)
real*8     , intent(in) :: H(:,:)

!local variables ...
integer :: i , j , mm
complex*16 :: erg_el , erg_hl

mm = size(AO_bra(:,1))

erg_el = (0.d0,0.d0)
erg_hl = (0.d0,0.d0)

If( eh_tag(1) == "el" ) then
    !$OMP parallel do private(i,j) default(shared) reduction(+ : erg_el )
    do j = 1 , mm
        do i = 1 , mm
            erg_el = erg_el + AO_bra(i,1)*H(i,j)*AO_ket(j,1)
        end do
    end do
    !$OMP end parallel do  
End If

If( eh_tag(2) == "hl" ) then
    !$OMP parallel do private(i,j) default(shared) reduction(+ : erg_hl)
    do j = 1 , mm
        do i = 1 , mm
            erg_hl = erg_hl + AO_bra(i,2)*H(i,j)*AO_ket(j,2)
        end do
    end do
    !$OMP end parallel do  
End If

Unit_Cell% QM_wp_erg(1) = erg_el
Unit_Cell% QM_wp_erg(2) = erg_hl

! QM_erg = E_occ - E_empty ; to be used in MM_dynamics energy balance ...
Unit_Cell% QM_erg = erg_el - erg_hl

end subroutine QuasiParticleEnergies
!
!
!
!
!=================================================================================
 subroutine preprocess_from_restart( system , basis , DUAL_ket , AO_bra , AO_ket )
!=================================================================================
implicit none
type(structure) , intent(inout) :: system
type(STO_basis) , intent(inout) :: basis(:)
complex*16      , intent(in)    :: DUAL_ket (:,:)
complex*16      , intent(in)    :: AO_bra   (:,:)
complex*16      , intent(in)    :: AO_ket   (:,:)

!local variables ...
integer :: N , err
integer :: mpi_D_R = mpi_double_precision

N = size(basis)

!vector states to be propagated ...
allocate( Psi_t_bra(N,n_part) )
allocate( Psi_t_ket(N,n_part) )

Psi_t_bra = DUAL_ket
Psi_t_ket = AO_ket

CALL Overlap_Matrix( system , basis , S_matrix )

allocate( h0(N,N) , source = D_zero )

!------------------------------------------------------------------------
If( master .OR. EnvCrew ) then 

   If( EnvField_ ) then
      ! EnCrew stay in even_more_extended_Huckel ...
      h0(:,:) = even_more_extended_Huckel( system , basis , S_matrix )
   Else
      h0(:,:) = Build_Huckel( basis , S_matrix )
   end If

   CALL MPI_BCAST( h0 , N*N , mpi_D_R , 0 , ForceComm , err )
   CALL MPI_BCAST( h0 , N*N , mpi_D_R , 0 , ChebyComm , err )

End If

If( ForceCrew ) then
   ! After instantiating S_matrix AND h0, ForceCrew leave to EhrenfestForce ...
   CALL MPI_BCAST( h0 , N*N , mpi_D_R , 0 , ForceComm , err )
   return
End If

! Another ChebyCrew  mate ...
If( myCheby == 1 ) CALL MPI_BCAST( h0 , N*N , mpi_D_R , 0 , ChebyComm , err )
!------------------------------------------------------------------------

CALL QuasiParticleEnergies(AO_bra, AO_ket, h0)

! IF QM_erg < 0 => turn off QMMM ; IF QM_erg > 0 => turn on QMMM ...
QMMM = (.NOT. (Unit_Cell% QM_erg < D_zero)) .AND. (HFP_Forces == .true.)

end subroutine preprocess_from_restart
!
!
!
end module ElHl_Chebyshev_m
