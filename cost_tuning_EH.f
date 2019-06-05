module cost_EH

    use type_m
    use constants_m
    use GA_QCModel_m   , only : Mulliken , Bond_Type , MO_character , Localize , Exclude


    public :: evaluate_cost , REF_DP , REF_Alpha

    ! module variables ...
    real*8 :: REF_DP(3) , REF_Alpha(3)

    private 

contains
!
!
!
!============================================================================
 function evaluate_cost( system , OPT_UNI , basis , DP , Alpha_ii , ShowCost)
!============================================================================
implicit none
type(structure)             , intent(in) :: system
type(R_eigen)               , intent(in) :: OPT_UNI
type(STO_basis)             , intent(in) :: basis(:)
real*8          , optional  , intent(in) :: DP(3)
real*8          , optional  , intent(in) :: Alpha_ii(3)
logical         , optional  , intent(in) :: ShowCost
real*8                                   :: evaluate_cost

! local variables ...
integer  :: i , dumb
real*8   :: chi(70)    = D_zero
real*8   :: weight(70) = D_one
real*8   :: REF_DP(3) , REF_Alpha(3)

!--------------------
! Energy gaps ...     
!--------------------
chi(1) = ( OPT_UNI%erg(50) - OPT_UNI%erg(49) )  - 6.4937d0           ; weight(1) = 1.5 
chi(2) = ( OPT_UNI%erg(51) - OPT_UNI%erg(49) )  - 7.9044d0           ; weight(2) = 1.0
chi(3) = ( OPT_UNI%erg(50) - OPT_UNI%erg(48) )  - 8.3523d0           ; weight(3) = 1.0
chi(4) = ( OPT_UNI%erg(49) - OPT_UNI%erg(48) )  - 1.8585d0           ; weight(4) = 2.0
chi(5) = ( OPT_UNI%erg(51) - OPT_UNI%erg(50) )  - 1.4106d0           ; weight(5) = 1.5
chi(6) = ( OPT_UNI%erg(48) - OPT_UNI%erg(47) )  - 0.0552d0           ; weight(6) = 1.0
chi(7) = ( OPT_UNI%erg(47) - OPT_UNI%erg(46) )  - 0.1978d0           ; weight(7) = 2.0
chi(8) = ( OPT_UNI%erg(52) - OPT_UNI%erg(51) )  - 0.1260d0           ; weight(8) = 1.0

!-------------------------------------------------------------------------
! MO character ...
! MO_character( OPT_UNI , basis , MO , AO )
! AO = s , py , pz , px , dxy , dyz , dz2 , dxz , dx2y2
! Localize( OPT_UNI , basis , MO , atom=[:] , residue )
! criterium: localized > 85% of total population
!-------------------------------------------------------------------------
chi( 9) =  MO_character(OPT_UNI, basis, MO=49, AO='Pz') 
chi(10) =  MO_character(OPT_UNI, basis, MO=48, AO='Pz') 
chi(11) =  MO_character(OPT_UNI, basis, MO=47, AO='Py') 
chi(12) =  MO_character(OPT_UNI, basis, MO=46, AO='Pz') 
chi(13) =  MO_character(OPT_UNI, basis, MO=50, AO='Pz') 
chi(14) =  MO_character(OPT_UNI, basis, MO=51, AO='Pz') 
chi(15) =  MO_character(OPT_UNI, basis, MO=53, AO='Pz') 

chi(16) =  Localize(OPT_UNI, basis, MO=49, residue = "GUA")    
chi(17) =  Localize(OPT_UNI, basis, MO=48, residue = "CYT")    
chi(18) =  Localize(OPT_UNI, basis, MO=47, residue = "GUA")    
chi(19) =  Localize(OPT_UNI, basis, MO=50, residue = "CYT")    
chi(20) =  Localize(OPT_UNI, basis, MO=51, residue = "CYT")    
chi(21) =  Localize(OPT_UNI, basis, MO=52, atom=[1:10])
chi(22) =  Localize(OPT_UNI, basis, MO=53, residue = "GUA")    

!-------------------------------------------------------------------------
! Bond Type analysis ...
! Bond_Type( system , OPT_UNI , MO , atom1 , atom2 , AO , "+" or "-" )
! AO = s , py , pz , px , dxy , dyz , dz2 , dxz , dx2y2
!  + = Bonding               &         - = Anti_Bonding
!-------------------------------------------------------------------------

chi(23) =  Bond_Type(system, OPT_UNI, 49, 21, 23, 'pz', '+')                                 
chi(24) =  Bond_Type(system, OPT_UNI, 49, 16, 15, 'Pz', '+')                                 
chi(25) =  Bond_Type(system, OPT_UNI, 49, 18, 17, 'Pz', '+')                                 
chi(26) =  Bond_Type(system, OPT_UNI, 49, 17, 24, 'Pz', '+')                                 
chi(27) =  Bond_Type(system, OPT_UNI, 49, 24, 14, 'Pz', '+')                                 
chi(28) =  Bond_Type(system, OPT_UNI, 49, 19, 18, 'Pz', '-')                                 
chi(29) =  Bond_Type(system, OPT_UNI, 49, 22, 21, 'Pz', '-')                                 
chi(30) =  Bond_Type(system, OPT_UNI, 49, 23, 24, 'Pz', '-')                                 
chi(31) =  Bond_Type(system, OPT_UNI, 49, 17, 16, 'Pz', '-')                                 
chi(32) =  Exclude(OPT_UNI, basis, MO=49, atom=[20]) 

chi(33) =  Bond_Type(system, OPT_UNI, 50,  5,  7, 'Pz', '+')                                 
chi(34) =  Bond_Type(system, OPT_UNI, 50,  3,  5, 'Pz', '-')                                 
chi(35) =  Bond_Type(system, OPT_UNI, 50,  3,  2, 'Pz', '-')                                 
chi(36) =  Bond_Type(system, OPT_UNI, 50,  7,  8, 'Pz', '-')                                 
chi(37) =  Bond_Type(system, OPT_UNI, 50,  7, 11, 'Pz', '-')                                 
chi(38) =  Bond_Type(system, OPT_UNI, 50, 11, 12, 'Pz', '+')                                 

chi(39) =  Bond_Type(system, OPT_UNI, 51,  2,  3, 'Pz', '+')                                 
chi(40) =  Bond_Type(system, OPT_UNI, 51, 11,  7, 'Pz', '+')                                 
chi(41) =  Bond_Type(system, OPT_UNI, 51, 12, 13, 'Pz', '-')                                 
chi(42) =  Bond_Type(system, OPT_UNI, 51,  7,  8, 'Pz', '-')                                 
chi(43) =  Bond_Type(system, OPT_UNI, 51,  7,  5, 'Pz', '-')                                
chi(44) =  Bond_Type(system, OPT_UNI, 51,  5,  3, 'Pz', '-')                                
chi(45) =  Bond_Type(system, OPT_UNI, 51, 12, 11, 'Pz', '-')                                

chi(46) =  Bond_Type(system, OPT_UNI, 48,  2, 11, 'Pz', '+')                                 
chi(47) =  Bond_Type(system, OPT_UNI, 48,  3,  5, 'Pz', '+')                                 
chi(48) =  Bond_Type(system, OPT_UNI, 48, 11,  8, 'Pz', '+')                                 
chi(49) =  Bond_Type(system, OPT_UNI, 48,  2,  3, 'Pz', '-')                                
chi(50) =  Bond_Type(system, OPT_UNI, 48, 13,  2, 'Pz', '-')                                
chi(51) =  Exclude(OPT_UNI, basis, MO=48, atom=[7], threshold =2.d-1) 

!chi(52) =  Bond_Type(system, OPT_UNI, 46,  5, 11, 'Pz', '+')                                
chi(61) =  Localize(OPT_UNI, basis, MO=46, atom=[5:13,18:23])    

!chi(53) =  Bond_Type(system, OPT_UNI, 53, 17, 18, 'Pz', '+')                                
!chi(54) =  Bond_Type(system, OPT_UNI, 53, 16, 24, 'Pz', '+')                                
!chi(55) =  Bond_Type(system, OPT_UNI, 53, 19, 18, 'Pz', '-')                                
!chi(56) =  Bond_Type(system, OPT_UNI, 53, 16, 17, 'Pz', '-')                                
!chi(57) =  Bond_Type(system, OPT_UNI, 53, 16, 15, 'Pz', '-')                                
!chi(58) =  Bond_Type(system, OPT_UNI, 53, 18, 20, 'Pz', '-')                                
!chi(59) =  Bond_Type(system, OPT_UNI, 53, 24, 23, 'Pz', '-')                                
!chi(60) =  Exclude(OPT_UNI, basis, MO=53, atom=[21], threshold =1.5d-1) 

! NO charge in these atoms ...
!-------------------------------------------------------------------------
! Exclude( OPT_UNI , basis , MO , atom=[:] , residue , threshold )
! default threshold < 1.d-3 
!-------------------------------------------------------------------------

!-------------------------------------------------------------------------
! Population analysis ...
! Mulliken( OPT_UNI , basis , MO , atom=[.,.,.] , AO_ang , EHSymbol , residue )
!-------------------------------------------------------------------------
! missing charge on these atoms ...

!-------------------------                                                         
! Total DIPOLE moment ...
!-------------------------

REF_DP = [ 0.d-4 , 1.85d0 , 0.0000d0 ]

!chi(6)  = DP(1) - REF_DP(1)     ; weight(6) = 1.d0
!chi(7)  = DP(2) - REF_DP(2)     ; weight(7) = 2.d0
!chi(8)  = DP(3) - REF_DP(3)     ; weight(8) = 1.d0

!-----------------------------------------------------
! Polarizability: Alpha tensor diagonal elements  ...
!-----------------------------------------------------

REF_Alpha = [ 9.2d0 , 8.5d0 , 7.8d0 ]

!chi(9)  = Alpha_ii(1) - REF_Alpha(1)     ; weight(9)  = 1.4d0
!chi(10) = Alpha_ii(2) - REF_Alpha(2)     ; weight(10) = 1.d0
!chi(11) = Alpha_ii(3) - REF_Alpha(3)     ; weight(11) = 1.4d0

!......................................................................
! at last, show the cost ...
If( present(ShowCost) ) then

   open( unit=33 , file='opt_trunk/view_cost.dat' , status='unknown' )

   do i = 1 , size(chi)
      write(33,*) i , dabs(chi(i)) , weight(i)
   end do 

end If
!......................................................................

! apply weight on chi and evaluate cost ...
chi = chi * weight
evaluate_cost = dot_product(chi,chi) 

! just touching basis ...
dumb = basis(1)%indx

end function evaluate_cost
!
!
!
end module cost_EH
