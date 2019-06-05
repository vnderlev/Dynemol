module diagnostic_m

 use type_m
 use omp_lib
 use constants_m
 use DOS_m
 use parameters_m               , only : spectrum , DP_Moment , &
                                         survival , DP_Field_ , &
                                         Alpha_Tensor ,         &
                                         GaussianCube ,         &
                                         EHM_Forces
 use Solvated_M                 , only : DeAllocate_TDOS ,      &
                                         DeAllocate_PDOS ,      &
                                         DeAllocate_SPEC 
 use Structure_Builder          , only : Unit_Cell ,            &
                                         Extended_Cell ,        &
                                         Generate_Structure ,   &
                                         Basis_Builder ,        &
                                         ExCell_basis
 use GA_QCModel_m               , only : Mulliken , GA_Eigen
 use DP_main_m                  , only : Dipole_Matrix
 use DP_potential_m             , only : Molecular_DPs
 use Oscillator_m               , only : Optical_Transitions
 use Psi_squared_cube_format    , only : Gaussian_Cube_Format
 use Data_Output                , only : Dump_stuff
 use Embedded_FF_Alpha          , only : AlphaPolar
 use HuckelForces_m             , only : HuckelForces

 public :: diagnostic

 private

 contains
!
!
!
!====================
subroutine diagnostic
!====================
implicit none 

! local variables ...
 integer                        :: i , nr , N_of_residues, MO_total
 integer         , allocatable  :: MOnum(:)
 character(6)                   :: MOstr
 real*8                         :: DP(3)
 type(R_eigen)                  :: UNI
 type(f_grid)                   :: TDOS , SPEC
 type(f_grid)    , allocatable  :: PDOS(:) 

 
! preprocessing stuff ...................................

IF ( survival ) pause " >>> quit: diagnostic driver does not carry q_dynamics calculations <<< "

CALL DeAllocate_TDOS( TDOS , flag="alloc" )
CALL DeAllocate_PDOS( PDOS , flag="alloc" )
CALL DeAllocate_SPEC( SPEC , flag="alloc" )

N_of_residues = size( Unit_Cell%list_of_residues )

! reading command line arguments for plotting MO cube files ...
MO_total  = COMMAND_ARGUMENT_COUNT()
allocate( MOnum(MO_total) )
do i = 1 , MO_total
    CALL GET_COMMAND_ARGUMENT(i, MOstr)
    read( MOstr,*) MOnum(i)
end do

!.........................................................

 CALL Generate_Structure(1)

 CALL Basis_Builder( Extended_Cell, ExCell_basis )

 If( DP_field_ )CALL Molecular_DPs( Extended_Cell )

 ! this Eigen is MPI free ...
 CALL GA_Eigen( Extended_Cell, ExCell_basis, UNI )

 ! save energies of the TOTAL system 
 OPEN(unit=9,file='system-ergs.dat',status='unknown')
     do i = 1 , size(ExCell_basis)
         write(9,*) i , UNI%erg(i)
     end do
 CLOSE(9) 

 CALL Total_DOS( UNI%erg , TDOS )

 do nr = 1 , N_of_residues
    CALL Partial_DOS( Extended_Cell , UNI , PDOS , nr )            
 end do

 If( DP_Moment .OR. Spectrum ) CALL Dipole_Matrix( Extended_Cell, ExCell_basis, UNI%L, UNI%R , DP )  

 If( Alpha_Tensor .AND. DP_Moment ) CALL AlphaPolar( Extended_Cell, ExCell_basis ) 

 If( Spectrum ) CALL Optical_Transitions( Extended_Cell, ExCell_basis, UNI , SPEC )

 If( EHM_Forces ) CALL HuckelForces( Extended_Cell, ExCell_basis, UNI )

 If( GaussianCube ) then
     do i = 1 , MO_total
         CALL Gaussian_Cube_Format( UNI%L(MOnum(i),:) , UNI%R(:,MOnum(i)) , MOnum(i) , 0.d0 )
     end do
 end if

Print*, " " 
Print*, "dE1 = ", UNI%erg(50) - UNI%erg(49) ,   7.6121d0
Print*, "dE2 = ", UNI%erg(51) - UNI%erg(49) ,   8.1395d0
Print*, "dE3 = ", UNI%erg(50) - UNI%erg(48) ,   8.3182d0
Print*, "dE4 = ", UNI%erg(49) - UNI%erg(48) ,   0.7061d0
Print*, "dE5 = ", UNI%erg(51) - UNI%erg(50) ,   0.5273d0
Print*, "dE6 = ", UNI%erg(48) - UNI%erg(47) ,   0.5143d0
Print*, "dE7 = ", UNI%erg(47) - UNI%erg(46) ,   0.2713d0
Print*, "dE8 = ", UNI%erg(52) - UNI%erg(51) ,   0.6835d0

 CALL Dump_stuff( TDOS , PDOS , SPEC )

 CALL DeAllocate_TDOS( TDOS , flag="dealloc" )
 CALL DeAllocate_PDOS( PDOS , flag="dealloc" )
 CALL DeAllocate_SPEC( SPEC , flag="dealloc" )

 include 'formats.h'

end subroutine diagnostic
!
!
!
end module diagnostic_m
