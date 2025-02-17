#include "cppdefs.h"
      MODULE mod_sources
!
!git $Id$
!svn $Id: mod_sources.F 1064 2021-05-10 19:55:56Z arango $
!================================================== Hernan G. Arango ===
!  Copyright (c) 2002-2021 The ROMS/TOMS Group                         !
!    Licensed under a MIT/X style license                              !
!    See License_ROMS.txt                                              !
!=======================================================================
!                                                                      !
!  Msrc       Maximum number of analytical point Sources/Sinks.        !
!  Nsrc       Number of point Sources/Sinks.                           !
!  Dsrc       Direction of point Sources/Sinks:                        !
!               Dsrc(:) = 0,  Along XI-direction.                      !
!               Dsrc(:) > 0,  Along ETA-direction.                     !
!  Fsrc       Point Source/Sinks identification flag:                  !
!               Fsrc(:) = 0,  All Tracer source/sink are off.          !
!               Fsrc(:) = 1,  Only temperature is on.                  !
!               Fsrc(:) = 2,  Only salinity is on.                     !
!               Fsrc(:) = 3,  Both temperature and salinity are on.    !
!               Fsrc(:) = 4,  Both nitrate and salinity are on.        !
!               Fsrc(:) = ... And other combinations.                  !
!                             (We need a more robust logic here)       !
!  Isrc       I-grid location of point Sources/Sinks,                  !
!               1 =< Isrc =< Lm(ng).                                   !
!  Jsrc       J-grid location of point Sources/Sinks,                  !
!               1 =< Jsrc =< Mm(ng).                                   !
!  Qbar       Vertically integrated mass transport (m3/s) of point     !
!               Sources/Sinks at U- or V-points:                       !
!               Qbar -> positive, if the mass transport is in the      !
!                       positive U- or V-direction.                    !
!               Qbar -> negative, if the mass transport is in the      !
!                       negative U- or V-direction.                    !
!  QbarG      Latest two-time snapshots of vertically integrated       !
!               mass transport (m3/s) of point Sources/Sinks.          !
!  Qshape     Nondimensional shape function to distribute mass         !
!               mass point Sources/Sinks vertically.                   !
!  Qsrc       Mass transport profile (m3/s) of point Sources/Sinks.    !
!  Tsrc       Tracer (tracer units) point Sources/Sinks.               !
!  TsrcG      Latest two-time snapshots of tracer (tracer units)       !
!               point Sources/Sinks.                                   !
#ifdef ICEPLUME
!                                                                      !
!  SGbar      Mass transport (m3/s) of subglacial Sources/Sinks.       !
!  SGbarG     Latest two-time snapshots of mass transport of           !
!                subglacial Sources/Sinks.                             !
!  SGtrc      Tracer (tracer units) of subglacial Sources/Sinks.       !
!  SGtrcG     Latest two-time snapshots of tracer (tracer units) of    !
!               subglacial Sources/Sinks.                              !
!  SGdep      Depth of subglacial point Sources/Sinks (m).             !
!  SGtyp      Type of subglacial point Sources/Sinks:                  !
!               SGtyp(:) = 0,  No subglaical discharge or melt.        !
!               SGtyp(:) = 1,  No subglaical discharge, only melt.     !
!               SGtyp(:) = 2,  half-cone (point source).               !
!               SGtyp(:) = 3,  finite-line.                            !
!               SGtyp(:) = 4,  sheet (infinite-line).                  !
!               SGtyp(:) = 5,  detached.                               !
!               SGtyp(:) = 6,  ellipse.                                !
!               SGtyp(:) = ... other types to be determined.           !
!  SGlen      Length of point Sources/Sinks (m).                       !
# ifdef ICEPLUME_SLOPE
!  SGang      Angle of the glacier front (degree).                     !
# endif
# ifdef ICEPLUME_SPREAD
!  SGgid      River/glacier ID number. The same ID suggests the point  !
!               sources/sinks belong to the same river/glacier.        !
# endif
# ifdef ICEPLUME_DET_AVERAGE
!  SGIrange   Location indices (I) when averaging density profiles.    !
!  SGJrange   Location indices (J) when averaging density profiles.    !
# endif
#endif
!                                                                      !
!=======================================================================
!
        USE mod_kinds
        USE mod_param
!
        implicit none
!
        integer, allocatable :: Msrc(:)
        integer, allocatable :: Nsrc(:)
!
        TYPE T_SOURCES

          integer, pointer :: Isrc(:)
          integer, pointer :: Jsrc(:)

          real(r8), pointer :: Dsrc(:)
          real(r8), pointer :: Fsrc(:)
          real(r8), pointer :: Qbar(:)
          real(r8), pointer :: Qshape(:,:)
          real(r8), pointer :: Qsrc(:,:)
          real(r8), pointer :: Tsrc(:,:,:)
          real(r8), pointer :: Xsrc(:)
          real(r8), pointer :: Ysrc(:)

#ifndef ANA_PSOURCE
          real(r8), pointer :: QbarG(:,:)
          real(r8), pointer :: TsrcG(:,:,:,:)
#endif

#ifdef ADJOINT
          real(r8), pointer :: ad_Qbar(:)
          real(r8), pointer :: ad_Qsrc(:,:)
          real(r8), pointer :: ad_Tsrc(:,:,:)
#endif

#ifdef TANGENT
          real(r8), pointer :: tl_Qbar(:)
          real(r8), pointer :: tl_Qsrc(:,:)
          real(r8), pointer :: tl_Tsrc(:,:,:)
#endif

#ifdef ICEPLUME
          real(r8), pointer :: SGbar(:)
          real(r8), pointer :: SGtrc(:,:)
# ifndef ANA_PSOURCE
          real(r8), pointer :: SGbarG(:,:)
          real(r8), pointer :: SGtrcG(:,:,:)
# endif
          real(r8), pointer :: SGdep(:)
          real(r8), pointer :: SGtyp(:)
          real(r8), pointer :: SGlen(:)
# ifdef ICEPLUME_SLOPE
          real(r8), pointer :: SGang(:)
# endif
# ifdef ICEPLUME_SPREAD
          real(r8), pointer :: SGgid(:)
# endif
# ifdef ICEPLUME_DET_AVERAGE
          real(r8), pointer :: SGIrange(:, :)
          real(r8), pointer :: SGJrange(:, :)
# endif
#endif

        END TYPE T_SOURCES

        TYPE (T_SOURCES), allocatable :: SOURCES(:)
!
      CONTAINS
!
      SUBROUTINE allocate_sources (ng)
!
!=======================================================================
!                                                                      !
!  This routine allocates and initializes all variables in the module  !
!  for all nested grids.                                               !
!                                                                      !
!=======================================================================
!
      USE mod_param
#ifndef ANA_PSOURCE
      USE mod_parallel
      USE mod_iounits
      USE mod_ncparam
      USE mod_netcdf
# if defined PIO_LIB && defined DISTRIBUTE
      USE mod_pio_netcdf
# endif
      USE mod_scalars
#endif
!
      USE strings_mod, ONLY : FoundError
!
!  Imported variable declarations.
!
      integer :: ng
!
!  Local variable declarations.
!
#ifndef ANA_PSOURCE
      logical :: foundit
!
      integer :: Vid, ifile, nvatt, nvdim
#endif
      integer :: is, itrc, k, mg

      real(r8), parameter :: IniVal = 0.0_r8
!
      character (len=*), parameter :: MyFile =                          &
     &  __FILE__//", allocate_sources"

#ifndef ANA_PSOURCE
# if defined PIO_LIB && defined DISTRIBUTE
!
      TYPE (Var_desc_t)  :: my_pioVar
# endif
#endif
!
!-----------------------------------------------------------------------
!  Allocate module variables.
!-----------------------------------------------------------------------
!
      IF (.not.allocated(Msrc)) THEN
        allocate ( Msrc(Ngrids) )
      END IF

      IF (.not.allocated(Nsrc)) THEN
        allocate ( Nsrc(Ngrids) )
      END IF

#ifndef ANA_PSOURCE
!
!  Inquire about the number of point sources.
!
      IF (ng.eq.1) THEN
        DO mg=1,Ngrids
          foundit=.FALSE.
          IF (LuvSrc(mg).or.LwSrc(mg).or.ANY(LtracerSrc(:,mg))) THEN
            SELECT CASE (AVG(ng)%IOtype)
              CASE (io_nf90)
                CALL netcdf_inq_var (ng, iNLM, SSF(mg)%name,            &
     &                               MyVarName = Vname(1,idRxpo),       &
     &                               SearchVar = foundit,               &
     &                               VarID = Vid,                       &
     &                               nVardim = nvdim,                   &
     &                               nVarAtt = nvatt)

# if defined PIO_LIB && defined DISTRIBUTE
              CASE (io_pio)
                CALL pio_netcdf_inq_var (ng, iNLM, SSF(mg)%name,        &
     &                                   MyVarName = Vname(1,idRxpo),   &
     &                                   SearchVar = foundit,           &
     &                                   pioVar = my_pioVar,            &
     &                                   nVardim = nvdim,               &
     &                                   nVarAtt = nvatt)
# endif
            END SELECT
            IF (FoundError(exit_flag, NoError, __LINE__, MyFile)) RETURN
            IF (foundit) THEN
              Nsrc(mg)=var_Dsize(1)         ! first dimension
              Msrc(mg)=Nsrc(mg)
            END IF
          END IF
        END DO
      END IF
#else
!
!  Set number of point sources to maximum number of analytical sources.
!  Notice that a maximum of 200 analytical sources are set-up here.
!
      Msrc(ng)=200
      Nsrc(ng)=Msrc(ng)
#endif
!
!  Allocate structure.
!
      IF (ng.eq.1) allocate ( SOURCES(Ngrids) )
!
!  Allocate point Sources/Sinks variables.
!
      allocate ( SOURCES(ng) % Isrc(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % Jsrc(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % Dsrc(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % Fsrc(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % Qbar(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % Qshape(Nsrc(ng),N(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng)*N(ng),r8)

      allocate ( SOURCES(ng) % Qsrc(Nsrc(ng),N(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng)*N(ng),r8)

      allocate ( SOURCES(ng) % Tsrc(Nsrc(ng),N(ng),NT(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng)*N(ng)*NT(ng),r8)

      allocate ( SOURCES(ng) % Xsrc(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % Ysrc(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

#ifndef ANA_PSOURCE
      allocate ( SOURCES(ng) % QbarG(Nsrc(ng),2) )
      Dmem(ng)=Dmem(ng)+2.0_r8*REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % TsrcG(Nsrc(ng),N(ng),2,NT(ng)) )
      Dmem(ng)=Dmem(ng)+2.0_r8*REAL(Nsrc(ng)*N(ng)*NT(ng),r8)
#endif

#ifdef ADJOINT
      allocate ( SOURCES(ng) % ad_Qbar(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % ad_Qsrc(Nsrc(ng),N(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng)*N(ng),r8)

      allocate ( SOURCES(ng) % ad_Tsrc(Nsrc(ng),N(ng),NT(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng)*N(ng)*NT(ng),r8)
#endif

#ifdef TANGENT
      allocate ( SOURCES(ng) % tl_Qbar(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % tl_Qsrc(Nsrc(ng),N(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng)*N(ng),r8)

      allocate ( SOURCES(ng) % tl_Tsrc(Nsrc(ng),N(ng),NT(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng)*N(ng)*NT(ng),r8)
#endif

#ifdef ICEPLUME
      allocate ( SOURCES(ng) % SGbar(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % SGtrc(Nsrc(ng),NT(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng)*NT(ng),r8)

# ifndef ANA_PSOURCE
      allocate ( SOURCES(ng) % SGbarG(Nsrc(ng),2) )
      Dmem(ng)=Dmem(ng)+2.0_r8*REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % SGtrcG(Nsrc(ng),2,NT(ng)) )
      Dmem(ng)=Dmem(ng)+2.0_r8*REAL(Nsrc(ng)*NT(ng),r8)

# endif
      allocate ( SOURCES(ng) % SGdep(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % SGtyp(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % SGlen(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

# ifdef ICEPLUME_SLOPE
      allocate ( SOURCES(ng) % SGang(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

# endif
# ifdef ICEPLUME_SPREAD
      allocate ( SOURCES(ng) % SGgid(Nsrc(ng)) )
      Dmem(ng)=Dmem(ng)+REAL(Nsrc(ng),r8)

# endif
# ifdef ICEPLUME_DET_AVERAGE
      allocate ( SOURCES(ng) % SGIrange(Nsrc(ng), 2) )
      Dmem(ng)=Dmem(ng)+2.0_r8*REAL(Nsrc(ng),r8)

      allocate ( SOURCES(ng) % SGJrange(Nsrc(ng), 2) )
      Dmem(ng)=Dmem(ng)+2.0_r8*REAL(Nsrc(ng),r8)

# endif
#endif

!
!-----------------------------------------------------------------------
!  Initialize module variables.
!-----------------------------------------------------------------------
!
      DO is=1,Nsrc(ng)
        SOURCES(ng) % Isrc(is) = 0
        SOURCES(ng) % Jsrc(is) = 0
        SOURCES(ng) % Dsrc(is) = IniVal
        SOURCES(ng) % Fsrc(is) = IniVal
        SOURCES(ng) % Xsrc(is) = IniVal
        SOURCES(ng) % Ysrc(is) = IniVal
        SOURCES(ng) % Qbar(is) = IniVal
#ifndef ANA_PSOURCE
        SOURCES(ng) % QbarG(is,1) = IniVal
        SOURCES(ng) % QbarG(is,2) = IniVal
#endif
#ifdef ADJOINT
        SOURCES(ng) % ad_Qbar(is) = IniVal
#endif
#ifdef TANGENT
        SOURCES(ng) % tl_Qbar(is) = IniVal
#endif
      END DO
      DO k=1,N(ng)
        DO is=1,Nsrc(ng)
          SOURCES(ng) % Qshape(is,k) = IniVal
          SOURCES(ng) % Qsrc(is,k) = IniVal
#ifdef ADJOINT
          SOURCES(ng) % ad_Qsrc(is,k) = IniVal
#endif
#ifdef TANGENT
          SOURCES(ng) % tl_Qsrc(is,k) = IniVal
#endif
        END DO
      END DO
      DO itrc=1,NT(ng)
        DO k=1,N(ng)
          DO is=1,Nsrc(ng)
            SOURCES(ng) % Tsrc(is,k,itrc) = IniVal
#ifdef ADJOINT
            SOURCES(ng) % ad_Tsrc(is,k,itrc) = IniVal
#endif
#ifdef TANGENT
            SOURCES(ng) % tl_Tsrc(is,k,itrc) = IniVal
#endif
#ifndef ANA_PSOURCE
            SOURCES(ng) % TsrcG(is,k,1,itrc) = IniVal
            SOURCES(ng) % TsrcG(is,k,2,itrc) = IniVal
#endif
          END DO
        END DO
      END DO

#ifdef ICEPLUME
      DO is=1,Nsrc(ng)
        SOURCES(ng) % SGbar(is) = IniVal
        SOURCES(ng) % SGdep(is) = IniVal
        SOURCES(ng) % SGtyp(is) = IniVal
        SOURCES(ng) % SGlen(is) = IniVal
# ifdef ICEPLUME_SLOPE
        SOURCES(ng) % SGang(is) = IniVal
# endif
# ifdef ICEPLUME_SPREAD
        SOURCES(ng) % SGgid(is) = IniVal
# endif
# ifdef ICEPLUME_DET_AVERAGE
        DO K = 1, 2
          SOURCES(ng) % SGIrange(is, K) = IniVal
          SOURCES(ng) % SGJrange(is, K) = IniVal
        ENDDO
# endif
      END DO
      DO itrc=1,NT(ng)
        DO is=1,Nsrc(ng)
          SOURCES(ng) % SGtrc(is,itrc) = IniVal
        END DO
      END DO
# ifndef ANA_PSOURCE
      DO is=1,Nsrc(ng)
        SOURCES(ng) % SGbarG(is,1) = IniVal
        SOURCES(ng) % SGbarG(is,2) = IniVal
      END DO
      DO itrc=1,NT(ng)
        DO is=1,Nsrc(ng)
          SOURCES(ng) % SGtrcG(is,1,itrc) = IniVal
          SOURCES(ng) % SGtrcG(is,2,itrc) = IniVal
        END DO
      END DO
# endif
#endif
!
      RETURN
      END SUBROUTINE allocate_sources
      END MODULE mod_sources
