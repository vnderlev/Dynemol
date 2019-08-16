module Chebyshev_m

    use type_m              , g_time => f_time  
    use constants_m
    use blas95
    use lapack95
    use ifport
    use parameters_m        , only : t_i , frame_step , DP_Field_ , driver ,  &
                                     n_part , restart , CT_dump_step                 
    use Structure_Builder   , only : Unit_Cell                                      
    use Overlap_Builder     , only : Overlap_Matrix
    use FMO_m               , only : FMO_analysis , eh_tag  
    use Data_Output         , only : Populations
    use Hamiltonians        , only : X_ij , even_more_extended_Huckel
    use Taylor_m            , only : Propagation, dump_Qdyn
    use Matrix_Math

    public  :: Chebyshev , preprocess_Chebyshev  

    private

! module parameters ...
    integer       , parameter   :: order       = 25
    real*8        , parameter   :: error       = 1.0d-12
    real*8        , parameter   :: norm_error  = 1.0d-12

! module variables ...
    logical       , save        :: necessary_  = .true.
    logical       , save        :: first_call_ = .true.
    real*8        , save        :: save_tau 
    real*8        , allocatable :: S_matrix(:,:)
    real*8, target, allocatable :: h0(:,:)
    complex*16    , allocatable :: Psi_t_bra(:) , Psi_t_ket(:)

    interface preprocess_Chebyshev
        module procedure preprocess_Chebyshev
        module procedure preprocess_from_restart
    end interface

contains
!
!
!
!=====================================================================================================
 subroutine preprocess_Chebyshev( system , basis , AO_bra , AO_ket , Dual_bra , Dual_ket , QDyn , it )
!=====================================================================================================
implicit none
type(structure) , intent(inout) :: system
type(STO_basis) , intent(inout) :: basis(:)
complex*16      , intent(out)   :: AO_bra(:)
complex*16      , intent(out)   :: AO_ket(:)
complex*16      , intent(out)   :: Dual_bra(:)
complex*16      , intent(out)   :: Dual_ket(:)
type(g_time)    , intent(inout) :: QDyn
integer         , intent(in)    :: it

!local variables ...
integer                         :: li , N 
real*8          , allocatable   :: wv_FMO(:)
complex*16      , allocatable   :: Psi(:)
type(R_eigen)                   :: FMO

!GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG
#ifdef USE_GPU
allocate( S_matrix(size(basis),size(basis)) )
call GPU_Pin(S_matrix, size(basis)*size(basis)*8)
#endif
!GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG

! MUST compute S_matrix before FMO analysis ...
CALL Overlap_Matrix( system , basis , S_matrix )
h0(:,:) = Build_Huckel( basis , S_matrix )
! for a rigid structure once is enough ...
If( driver == 'q_dynamics' ) necessary_ = .false.

!=======================================================================
! prepare  DONOR  state ...
CALL FMO_analysis( system , basis, FMO=FMO , MO=wv_FMO , instance="E" )

! place the  DONOR  state in Structure's hilbert space ...
li = minloc( basis%indx , DIM = 1 , MASK = basis%El )
N  = size(wv_FMO)
allocate( Psi(size(basis)) , source=C_zero )
Psi(li:li+N-1) = dcmplx( wv_FMO(:) )
deallocate( wv_FMO )
!======================================================================

!==============================================
! prepare DUAL basis for local properties ...
! DUAL_bra = (C*)^T    ;    DUAL_ket = S*C ...
DUAL_bra = dconjg( Psi )
call op_x_ket( DUAL_ket, S_matrix , Psi )
!==============================================

!==============================================
!vector states to be propagated ...
!Psi_bra = C^T*S       ;      Psi_ket = C ...
allocate( Psi_t_bra(size(basis)) )
allocate( Psi_t_ket(size(basis)) )
call bra_x_op( Psi_t_bra, Psi , S_matrix )
Psi_t_ket = Psi
!==============================================

!==============================================
AO_bra = Psi
AO_ket = Psi
!==============================================

! save populations(time=t_i) ...
QDyn%dyn(it,:,1) = Populations( QDyn%fragments , basis , DUAL_bra , DUAL_ket , t_i )
CALL dump_Qdyn( Qdyn , it )

! leaving S_matrix allocated

end subroutine preprocess_Chebyshev
!
!
!
!=========================================================================================================
 subroutine Chebyshev(  system , basis , AO_bra , AO_ket , Dual_bra , Dual_ket , QDyn , t , delta_t , it )
!=========================================================================================================
implicit none
type(structure)  , intent(in)    :: system
type(STO_basis)  , intent(in)    :: basis(:)
complex*16       , intent(inout) :: AO_bra(:)
complex*16       , intent(inout) :: AO_ket(:)
complex*16       , intent(inout) :: Dual_bra(:)
complex*16       , intent(inout) :: Dual_ket(:)
type(g_time)     , intent(inout) :: QDyn
real*8           , intent(inout) :: t
real*8           , intent(in)    :: delta_t
integer          , intent(in)    :: it

! local variables... 
integer                     :: N
real*8                      :: tau , tau_max , t_init, t_max 
real*8      , allocatable   :: H_prime(:,:)
real*8      , pointer       :: h(:,:)

t_init = t

! max time inside slice ...
t_max = delta_t*frame_step*(it-1)  
! constants of evolution ...
tau_max = delta_t / h_bar

! trying to adapt time step for efficient propagation ...
tau = merge( tau_max , save_tau * 1.15d0 , first_call_ )
! but tau should be never bigger than tau_max ...
tau = merge( tau_max , tau , tau > tau_max )

N = size(basis)

if(first_call_) then           ! allocate matrices
#ifdef USE_GPU
!GGGGGGGGGGGGGGGGGGGGGGGGGGGGG

    allocate( H(N,N) )         ! no need of H_prime in the cpu: will be calculated in the gpu
    call GPU_Pin( H, N*N*8 )
!GGGGGGGGGGGGGGGGGGGGGGGGGGGGG
#else
    allocate( H(N,N) , H_prime(N,N) )
#endif
end if

If ( necessary_ ) then ! <== not necessary for a rigid structures ...

    ! compute S and S_inverse ...
    CALL Overlap_Matrix( system , basis , S_matrix )

    h0(:,:) = Build_Huckel( basis , S_matrix )

    CALL syInvert( S_matrix, return_full )   ! S_matrix content is destroyed and S_inv is returned
#define S_inv S_matrix

end If

h => h0

#ifndef USE_GPU
! allocate and compute H' = S_inv * H ...
If (.not. allocated(H_prime) ) allocate( H_prime(N,N) )
call syMultiply( S_inv , h , H_prime )
#endif

! proceed evolution of ELECTRON wapacket with best tau ...
#ifdef USE_GPU
!GGGGGGGGGGGGGGGGGGGGGGGGGGGGG
call PropagationElHl_gpucaller(_electron_, Coulomb_, N, S_inv(1,1), h(1,1), Psi_t_bra(1), Psi_t_ket(1), t_init, t_max, tau, save_tau)
!GGGGGGGGGGGGGGGGGGGGGGGGGGGGG
#else
call Propagation( N , H_prime , Psi_t_bra , Psi_t_ket , t_init , t_max , tau , save_tau )
#endif

t = t_init + (delta_t*frame_step)

! prepare DUAL basis for local properties ...
DUAL_bra = dconjg(Psi_t_ket)
DUAL_ket = Psi_t_bra

! prepare Slater basis for FORCE properties ...
call op_x_ket( AO_bra, S_inv, Psi_t_bra )
AO_bra = dconjg(AO_bra)
AO_ket = Psi_t_ket

! save populations(time) ...
QDyn%dyn(it,:,1) = Populations( QDyn%fragments , basis , DUAL_bra , DUAL_ket , t )

if( mod(it,CT_dump_step) == 0 ) CALL dump_Qdyn( Qdyn , it )

! clean and exit ...
If( driver /= 'q_dynamics' ) then
    deallocate( h0 )
    nullify( h )
end if
#ifndef USE_GPU
deallocate( H_prime )
#endif
#undef S_inv

Print 186, t

first_call_ = .false.

include 'formats.h'

end subroutine Chebyshev
!
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
integer :: i , j , N
real*8  , allocatable   :: h(:,:)

!----------------------------------------------------------
!      building  the  HUCKEL  HAMILTONIAN

N = size(basis)
ALLOCATE( h(N,N) , source = D_zero )

do j = 1 , N
  do i = j , N

        h(i,j) = X_ij( i , j , basis ) * S_matrix(i,j)

    end do
end do

end function Build_Huckel
!
!
!
!
!=================================================================================
 subroutine preprocess_from_restart( system , basis , DUAL_ket , AO_bra , AO_ket)
!=================================================================================
implicit none
type(structure) , intent(inout) :: system
type(STO_basis) , intent(inout) :: basis(:)
complex*16      , intent(in)    :: DUAL_ket (:)
complex*16      , intent(in)    :: AO_bra   (:)
complex*16      , intent(in)    :: AO_ket   (:)

!vector states to be propagated ...
allocate( Psi_t_bra(size(basis)) )
allocate( Psi_t_ket(size(basis)) )

Psi_t_bra = DUAL_ket
Psi_t_ket = AO_ket

CALL Overlap_Matrix( system , basis , S_matrix )
h0(:,:) = Build_Huckel( basis , S_matrix )

end subroutine preprocess_from_restart
!
!
!
end module Chebyshev_m


