#include "cppdefs.h"
      MODULE WAVES_COUPLER_MOD

#if defined MODEL_COUPLING && defined MCT_LIB
!
!git $Id$
!svn $Id: waves_coupler.F 1054 2021-03-06 19:47:12Z arango $
!==================================================== John C. Warner ===
!  Copyright (c) 2002-2021 The ROMS/TOMS Group      Hernan G. Arango   !
!   Licensed under a MIT/X style license                               !
!   See License_ROMS.txt                                               !
!=======================================================================
!                                                                      !
!  This module is used to communicate and exchange data between SWAN   !
!  other coupled model(s) using the Model Coupling Toolkit (MCT).      !
!                                                                      !
!=======================================================================
!
!  Componenet model registry.
!
      USE m_MCTWorld, ONLY : MCTWorld_init => init
      USE m_MCTWorld, ONLY : MCTWorld_clean => clean
!
!  Domain decompositin descriptor datatype and assocoiated methods.
!
      USE m_GlobalSegMap, ONLY : GlobalSegMap
      USE m_GlobalSegMap, ONLY : GlobalSegMap_init => init
      USE m_GlobalSegMap, ONLY : GlobalSegMap_lsize => lsize
      USE m_GlobalSegMap, ONLY : GlobalSegMap_clean => clean
      USE m_GlobalSegMap, ONLY : GlobalSegMap_Ordpnts => OrderedPoints
!
!  Field storage data types and associated methods.
!
      USE m_AttrVect, ONLY : AttrVect
      USE m_AttrVect, ONLY : AttrVect_init => init
      USE m_AttrVect, ONLY : AttrVect_zero => zero
      USE m_AttrVect, ONLY : AttrVect_clean => clean
      USE m_AttrVect, ONLY : AttrVect_indxR => indexRA
      USE m_AttrVect, ONLY : AttrVect_importRAttr => importRAttr
      USE m_AttrVect, ONLY : AttrVect_exportRAttr => exportRAttr
!
!  Intercomponent communitcations scheduler.
!
      USE m_Router, ONLY : Router
      USE m_Router, ONLY : Router_init => init
      USE m_Router, ONLY : Router_clean => clean
!
!  Intercomponent transfer.
!
      USE m_Transfer, ONLY : MCT_Send => send
      USE m_Transfer, ONLY : MCT_Recv => recv
!
      implicit none
!
      PRIVATE

      PUBLIC :: initialize_wav2ocn_coupling
      PUBLIC :: wav2ocn_coupling
      PUBLIC :: finalize_wav2ocn_coupling

# ifdef WRF_COUPLING
      PUBLIC :: initialize_wav2atm_coupling
      PUBLIC :: wav2atm_coupling
      PUBLIC :: finalize_wav2atm_coupling
# endif

      include 'mpif.h'
!
!  Declarations.
!
      TYPE(GlobalSegMap) :: GSMapSWAN         ! GloabalSegMap variables

      TYPE(AttrVect) :: wav2ocn_AV            ! AttrVect variables
      TYPE(AttrVect) :: ocn2wav_AV
      type(Router)   :: SWANtoROMS            ! Router variables

# if defined WRF_COUPLING
      TYPE(AttrVect) :: atm2wav_AV            ! AttrVec variables
      type(Router)   :: WRFtoSWAN             ! Router variables
# endif

      CONTAINS

      SUBROUTINE INITIALIZE_WAV2OCN_COUPLING
!
!=======================================================================
!                                                                      !
!  Initialize waves and ocean models coupling stream.  This is the     !
!  training phase use to constuct  MCT  parallel interpolators and     !
!  stablish communication patterns.                                    !
!                                                                      !
!=======================================================================
!
      USE OCPCOMM4
      USE SWCOMM3
      USE M_GENARR
      USE M_PARALL
      USE mod_coupler
!
      include 'mpif.h'
!
!  Local variable declarations.
!
      integer :: MyError, MyRank
      integer :: npoints, gsmsize, nprocs, localsize
      integer :: j, Isize, Jsize

      integer, pointer :: start(:), length(:)
!
!-----------------------------------------------------------------------
!  Begin initialization phase.
!-----------------------------------------------------------------------
!
!  Get communicator local rank and size.
!
      CALL mpi_comm_rank (WAV_COMM_WORLD, MyRank, MyError)
      CALL mpi_comm_size (WAV_COMM_WORLD, nprocs, MyError)
!
!  Initialize MCT coupled model registry.
!
      CALL MCTWorld_init (Nmodels, MPI_COMM_WORLD, WAV_COMM_WORLD,      &
     &                    WAVid)
!
!  Initialize a Global Segment Map for non-haloed transfer of data out
!  of SWAN. Determine non-haloed start and length arrays for this
!  processor.
!
      IF (nprocs.eq.1) THEN
        Isize=MXCGL
        Jsize=MYCGL
      ELSE
        IF (MXCGL.gt.MYCGL) THEN
          Isize=MXC-IHALOX*IBLKAD(1)
          Jsize=MYC
        ELSE
          Isize=MXC
          Jsize=MYC-IHALOY*IBLKAD(1)
        END IF
      END IF
!
      allocate ( start(Jsize) )
      allocate ( length(Jsize) )
!
      DO j=1,Jsize
        length(j)=ISIZE
        IF (MXCGL.gt.MYCGL) THEN
          IF (MyRank.eq.0) THEN
            start(j)=MXF+(j-1)*MXCGL
          ELSE
            start(j)=MXF+(j-1)*MXCGL+IHALOX
          END IF
        ELSE
          IF (MyRank.eq.0) THEN
            start(j)=MYF+(j-1)*MXCGL
          ELSE
            start(j)=(MYF+IHALOY-1)*MXCGL+1+(j-1)*MXCGL
          END IF
        END IF
      END DO
      gsmsize=Isize*Jsize
!
      CALL GlobalSegMap_init (GSMapSWAN, start, length, 0,              &
     &                        WAV_COMM_WORLD, WAVid)
!
!  Initialize attribute vector holding the export data code strings of
!  the wave model.
!
      CALL AttrVect_init (wav2ocn_AV, rlist=TRIM(ExportList(Iwaves)),   &
     &                    lsize=gsmsize)
      CALL AttrVect_zero (wav2ocn_AV)
!
!  Initialize attribute vector holding the export data code string of
!  the ocean model.
!
      CALL AttrVect_init (ocn2wav_AV, rList=TRIM(ExportList(Iocean)),   &
     &                    lsize=gsmsize)
      CALL AttrVect_zero (ocn2wav_AV)
!
!  Initialize a router to the waves model component.
!
      CALL Router_init (OCNid, GSMapSWAN, WAV_COMM_WORLD, SWANtoROMS)
!
# ifdef WRF_COUPLING
!
!  Initialize attribute vector holding the export data code string of
!  the atmosphere model.
!
      CALL AttrVect_init (atm2wav_AV, rList=TRIM(ExportList(Iatmos)),   &
     &                    lsize=gsmsize)
      CALL AttrVect_zero (atm2wav_AV)
!
! Initialize a router to the WRF component.
!
      CALL Router_init (ATMid, GSMapSWAN, WAV_COMM_WORLD, WRFtoSWAN)
!
# endif

      deallocate (start)
      deallocate (length)

      RETURN
      END SUBROUTINE INITIALIZE_WAV2OCN_COUPLING

      SUBROUTINE WAV2OCN_COUPLING (MIP, NVOQP, VOQR, VOQ, IRQ,          &
     &                             IVTYPE, COMPDA, numsteps)
!
!=======================================================================
!                                                                      !
!  This subroutine reads and writes the coupling data streams between  !
!  ocean and wave models. Currently, the following data streams are    !
!  processed:                                                          !
!                                                                      !
!  Fields exported to the OCEAN model:                                 !
!                                                                      !
!     * Wave direction (degrees)                                       !
!     * Significant wave height (m)                                    !
!     * Average wave length (m)                                        !
!     * Surface wave relative peak period (s)                          !
!     * Bottom wave period (s)                                         !
!     * Percent of breakig waves (nondimensional)                      !
!     * Wave energy dissipation (W/m2)                                 !
!     * Wave bottom orbital velocity (m/s)                             !
!                                                                      !
!  Fields imported from the OCEAN Model:                               !
!                                                                      !
!     * Bathymetry, bottom elevation (m)                               !
!     * Free-surface, water surface elevation (m)                      !
!     * Depth integrated u-momentum (m/s)                              !
!     * Depth integrated v-momentum (m/s)                              !
!                                                                      !
!=======================================================================
!
      USE SWCOMM3
      USE SWCOMM4
      USE OUTP_DATA
      USE M_PARALL
      USE M_GENARR
      USE M_MPI
      USE SWCOMM1
      USE mod_coupler
!
      implicit none
!
!  Imported variable declarations.
!
      integer :: MIP, IRQ, nvoqp, numsteps
      integer :: VOQR(NMOVAR), IVTYPE, IP, IX, IY

      real :: COMPDA(MCGRD,MCMVAR)
      real :: VOQ(MIP,NVOQP)
!
!  Local variable declarations.
!
      integer :: MyStatus, i, id, ifield, j, gsmsize, ierr, MyRank
      integer :: MyError, MySize, indx, Istr, Iend, Jstr, Jend
      integer :: Isize, Jsize, INDXG, NPROCS, OFFSET
      integer :: NUMTRANSFER, NNEIGH, HALOSIZE, NUMSENT, INB
      integer :: WHICHWAY, GDEST, GSRC, TAGT, TAGB, TAGR, TAGL
      integer :: TREQUEST,BREQUEST,RREQUEST,LREQUEST,MSIZE
      integer :: handle(2)

      integer, save :: Iexport = 0
      integer, save :: Iimport = 0

      integer, dimension(MPI_STATUS_SIZE,4) :: status
      integer, pointer :: points(:)

      real :: cff
      real(r8) :: RecvTime, SendTime, wtime(2)
      real(r8) :: inpbuffer(2), outbuffer(2)

      real(r8) :: my_wtime

      real(r8), pointer :: avdata(:)

      real, pointer :: TEMPMCT(:,:)
      real, pointer :: GRECVT(:), GRECVB(:), GRECVR(:), GRECVL(:)
      real, pointer :: GSENDT(:), GSENDB(:), GSENDR(:), GSENDL(:)

      character (len=40) :: code
!
!-----------------------------------------------------------------------
!  Send wave fields to ROMS.
!-----------------------------------------------------------------------
!
      CALL MPI_COMM_RANK (WAV_COMM_WORLD, MyRank, MyError)
      CALL MPI_COMM_SIZE (WAV_COMM_WORLD, NPROCS, MyError)
!
!  Get the number of grid point on this processor.
!
      gsmsize=GlobalSegMap_lsize(GSMapSWAN, WAV_COMM_WORLD)
!
!  Allocate attribute vector array used to export/import data.
!
      allocate ( avdata(gsmsize),stat=ierr )
!!    allocate ( points(gsmsize),stat=ierr )
      avdata=0.0_r8
!!    points=0
!
!  Ask for points in this tile.
!
      CALL GlobalSegMap_Ordpnts (GSMapSWAN, MyRank, points)
!
!  Load SWAN exporting data into MCT storage buffers.  Since this
!  routine is called several times from main, only load field
!  according to the IVTYPE flag.  The data is exported using ROMS
!  definition for real kind r8.
!
      IF (IVTYPE.le.50) THEN
        DO IP=1,gsmsize
          avdata(IP)=REAL( VOQ(points(IP),VOQR(IVTYPE)),r8 )
        END DO
!
        DO ifield=1,Nexport(Iwaves)
          id=ExportID(Iwaves)%val(ifield)
          code=ADJUSTL(Fields(id)%code)
          IF ((TRIM(code).eq.'Wdiss').and.(IVTYPE.eq.7)) THEN
            CALL AttrVect_importRAttr (wav2ocn_AV, TRIM(code), avdata)
            Iexport=Iexport+1
          ELSE IF ((TRIM(code).eq.'Wamp' ).and.(IVTYPE.eq.10)) THEN
            CALL AttrVect_importRAttr (wav2ocn_AV, TRIM(code), avdata)
            Iexport=Iexport+1
          ELSE IF ((TRIM(code).eq.'Wptop').and.(IVTYPE.eq.12)) THEN
            CALL AttrVect_importRAttr (wav2ocn_AV, TRIM(code), avdata)
            Iexport=Iexport+1
          ELSE IF ((TRIM(code).eq.'TM01' ).and.(IVTYPE.eq.11)) THEN
            CALL AttrVect_importRAttr (wav2ocn_AV, TRIM(code), avdata)
            Iexport=Iexport+1
          ELSE IF ((TRIM(code).eq.'Wpbot').and.(IVTYPE.eq.50)) THEN
            CALL AttrVect_importRAttr (wav2ocn_AV, TRIM(code), avdata)
            Iexport=Iexport+1
          ELSE IF ((TRIM(code).eq.'Wubot').and.(IVTYPE.eq.6 )) THEN
            CALL AttrVect_importRAttr (wav2ocn_AV, TRIM(code), avdata)
            Iexport=Iexport+1
          ELSE IF ((TRIM(code).eq.'Wdir' ).and.(IVTYPE.eq.13)) THEN
            CALL AttrVect_importRAttr (wav2ocn_AV, TRIM(code), avdata)
            Iexport=Iexport+1
          ELSE IF ((TRIM(code).eq.'Wlen' ).and.(IVTYPE.eq.17)) THEN
            CALL AttrVect_importRAttr (wav2ocn_AV, TRIM(code), avdata)
            Iexport=Iexport+1
          ELSE IF ((TRIM(code).eq.'Wbrk' ).and.(IVTYPE.eq.8 )) THEN
            CALL AttrVect_importRAttr (wav2ocn_AV, TRIM(code), avdata)
            Iexport=Iexport+1
          END IF
        END DO
      END IF
!
      IF (IRQ.eq.NREOQ) THEN
!
!  Initialize coupling wait time clocks.
!
        RecvTime=0.0_r8
        SendTime=0.0_r8
!
!-----------------------------------------------------------------------
!  Create a restart file.
!-----------------------------------------------------------------------
!
        CALL BACKUP (AC2, SPCSIG, SPCDIR, KGRPNT, XCGRID, YCGRID)
!
!-----------------------------------------------------------------------
!  Send wave fields bundle to ocean model, ROMS.
!-----------------------------------------------------------------------
!
        inpbuffer(2)=my_wtime(wtime)
        CALL MCT_Send (wav2ocn_AV, SWANtoROMS, MyError)
        SendTime=SendTime+my_wtime(wtime)-inpbuffer(2)
        IF (MyError.ne.0) THEN
          IF (MyRank.eq.0) THEN
            WRITE (6,10) 'ocean model, MyError = ', MyError
          END IF
!!        CALL finalize_wav2ocn_coupling
        END IF
!
!-----------------------------------------------------------------------
!  Receive from ROMS: Depth, Water Level, VELX, and VELY.
!-----------------------------------------------------------------------
!
!  Schedule receiving field from ocean model.
!
        inpbuffer(1)=my_wtime(wtime)
        CALL MCT_Recv (ocn2wav_AV, SWANtoROMS, MyError)
        RecvTime=RecvTime+my_wtime(wtime)-inpbuffer(1)
        IF (MyError.ne.0) THEN
          IF (MyRank.eq.0) THEN
             WRITE (6,20) 'ocean model, MyError = ', MyError
          END IF
!!        CALL finalize_wav2ocn_coupling
        END IF

# ifdef ATM_COUPLING
!
!  Schedule receiving fields from atmosphere model.
!
!       IF (numsteps.gt.1) THEN
          inpbuffer(1)=my_wtime(wtime)
          CALL MCT_Recv (atm2wav_AV, WRFtoSWAN, MyError)
          RecvTime=RecvTime+my_wtime(wtime)-inpbuffer(1)
          IF (MyError.ne.0) THEN
            IF (MyRank.eq.0) THEN
              WRITE (6,20) 'atmosphere model, MyError = ', MyError
            END IF
!!          CALL finalize_wav2ocn_coupling
          END IF
!       END IF
# endif
!
! Pass the non-halo data from MCT into tempmct array.
!
        NUMTRANSFER=Nimport(Iwaves)
!
        NNEIGH = IBLKAD(1)
        IF (nprocs.eq.1) THEN
          Istr=1
          Iend=MXC
          Jstr=1
          Jend=MYC
        ELSE
          IF (MXCGL.GT.MYCGL) THEN
            IF (MyRank.eq.0) THEN
              Istr=1
            ELSE
              Istr=IHALOX+1
            END IF
            Isize=MXC-IHALOX*IBLKAD(1)
            Iend=Istr+Isize-1
            Jstr=1
            Jend=MYC
            HALOSIZE=IHALOX*MYC
          ELSE
            IF (MyRank.eq.0) THEN
              Jstr=1
            ELSE
              Jstr=IHALOY+1
            END IF
            Jsize=MYC-IHALOY*IBLKAD(1)
            Jend=Jstr+Jsize-1
            Istr=1
            Iend=MXC
            HALOSIZE=IHALOY*MXC
          END IF
        END IF
!
        allocate ( TEMPMCT(MXC*MYC,NUMTRANSFER),stat=ierr )
        TEMPMCT=0.0

        Iimport=0
        DO ifield=1,Nimport(Iwaves)
          id=ImportID(Iwaves)%val(ifield)
          code=ADJUSTL(Fields(id)%code)

          SELECT CASE (TRIM(code))

            CASE ('bath')               ! bathymetry

              CALL AttrVect_exportRAttr (ocn2wav_AV, TRIM(code),        &
     &                                   avdata, gsmsize)
              Iimport=Iimport+1
              IP=0
              DO IY=Jstr,Jend
                DO IX=Istr,Iend
                  IP=IP+1
                  INDXG=(IY-1)*MXC+IX
                  TEMPMCT(INDXG,1)=REAL( avdata(IP) )
                END DO
              END DO

            CASE ('SSH')                ! Water surface elevation.

              CALL AttrVect_exportRAttr (ocn2wav_AV, TRIM(code),        &
     &                                   avdata, gsmsize)
              Iimport=Iimport+1
              IP=0
              DO IY=Jstr,Jend
                DO IX=Istr,Iend
                  IP=IP+1
                  INDXG=(IY-1)*MXC+IX
                  TEMPMCT(INDXG,2)=REAL( avdata(IP) )
                END DO
              END DO

            CASE ('Ubar')               ! Depth-integrated u-velocity

              CALL AttrVect_exportRAttr (ocn2wav_AV, TRIM(code),        &
     &                                   avdata, gsmsize)
              Iimport=Iimport+1
              IP=0
              DO IY=Jstr,Jend
                DO IX=Istr,Iend
                  IP=IP+1
                  INDXG=(IY-1)*MXC+IX
                  TEMPMCT(INDXG,3)=REAL( avdata(IP) )
                END DO
              END DO

            CASE ('Vbar')               !  Depth-integrated v-velocity

              CALL AttrVect_exportRAttr (ocn2wav_AV, TRIM(code),        &
     &                                   avdata, gsmsize)
              Iimport=Iimport+1
              IP=0
              DO IY=Jstr,Jend
                DO IX=Istr,Iend
                  IP=IP+1
                  INDXG=(IY-1)*MXC+IX
                  TEMPMCT(INDXG,4)=REAL( avdata(IP) )
                END DO
              END DO

            CASE ('ZO')               !  Bottom roughness

              CALL AttrVect_exportRAttr (ocn2wav_AV, TRIM(code),        &
     &                                   avdata, gsmsize)
              Iimport=Iimport+1
              IP=0
              DO IY=Jstr,Jend
                DO IX=Istr,Iend
                  IP=IP+1
                  INDXG=(IY-1)*MXC+IX
                  TEMPMCT(INDXG,5)=REAL( avdata(IP) )
                END DO
              END DO

# ifdef ATM_COUPLING

            CASE ('Uwind')               ! surface wind u-velocity

              CALL AttrVect_exportRAttr (atm2wav_AV, TRIM(code),        &
     &                                   avdata, gsmsize)
              Iimport=Iimport+1
              IP=0
              DO IY=Jstr,Jend
                DO IX=Istr,Iend
                  IP=IP+1
                  INDXG=(IY-1)*MXC+IX
                  TEMPMCT(INDXG,6)=REAL( avdata(IP) )
                END DO
              END DO

            CASE ('Vwind')              ! surface wind v-velocity

              CALL AttrVect_exportRAttr (atm2wav_AV, TRIM(code),        &
     &                                   avdata, gsmsize)
              Iimport=Iimport+1
              IP=0
              DO IY=Jstr,Jend
                DO IX=Istr,Iend
                  IP=IP+1
                  INDXG=(IY-1)*MXC+IX
                  TEMPMCT(INDXG,7)=REAL( avdata(IP) )
                END DO
              END DO
# endif
          END SELECT
        END DO
!
!  Report.
!
        IF (Nthreads(Iwaves).gt.1) THEN
          inpbuffer(1)=RecvTime
          inpbuffer(2)=SendTime
          handle(1)=MPI_SUM
          handle(2)=MPI_SUM
          CALL mpi_allreduce (inpbuffer, outbuffer, 2,                  &
     &                        MPI_DOUBLE_PRECISION, handle,             &
     &                        WAV_COMM_WORLD, MyError)
          RecvTime=outbuffer(1)
          SendTime=outbuffer(2)
        END IF
        IF (MyRank.eq.0) THEN
          IF ((Iimport.gt.0).or.(Iexport.gt.0)) THEN
            WRITE (6,30) Iimport, Iexport, TRIM(CHTIME),                &
     &                   RecvTime, SendTime
           CALL my_flush (6)
          END IF
        END IF
        Iexport=0
!
!  Pack and send halo regions to be exchanged with adjacent tiles.
!  IBLKAD contains the tile data.
!  WHICHWAY: [top, bot, right, left] = [1 2 3 4]
!
        IF (NPROCS.GT.1) THEN
          MSIZE=HALOSIZE*NUMTRANSFER
          IF (MXCGL.GT.MYCGL) THEN
            allocate ( GSENDR(MSIZE),stat=ierr )
            allocate ( GSENDL(MSIZE),stat=ierr )
            allocate ( GRECVR(MSIZE),stat=ierr )
            allocate ( GRECVL(MSIZE),stat=ierr )
            GSENDR=0.0
            GSENDL=0.0
            GRECVR=0.0
            GRECVL=0.0
          ELSE
            allocate ( GSENDT(MSIZE),stat=ierr )
            allocate ( GSENDB(MSIZE),stat=ierr )
            allocate ( GRECVT(MSIZE),stat=ierr )
            allocate ( GRECVB(MSIZE),stat=ierr )
            GSENDT=0.0
            GSENDB=0.0
            GRECVT=0.0
            GRECVB=0.0
          END IF
          TAGT=1
          TAGB=2
          TAGR=3
          TAGL=4
          DO INB=1,NNEIGH
            OFFSET=0
            WHICHWAY=IBLKAD(3*INB)
            DO NUMSENT=1,NUMTRANSFER
              IP=OFFSET
              IF (WHICHWAY.EQ.1) THEN
                DO IY=MYC-IHALOX-2,MYC-3
                  DO IX=1,MXC
                    IP=IP+1
                    INDXG=(IY-1)*MXC+IX
                    GSENDT(IP)=TEMPMCT(INDXG,NUMSENT)
                  END DO
                END DO
              ELSE IF (WHICHWAY.EQ.2) THEN
                DO IY=IHALOY+1,IHALOY+3
                  DO IX=1,MXC
                    IP=IP+1
                    INDXG=(IY-1)*MXC+IX
                    GSENDB(IP)=TEMPMCT(INDXG,NUMSENT)
                  END DO
                END DO
              ELSE IF (WHICHWAY.EQ.3) THEN
                DO IY=1,MYC
                  DO IX=MXC-IHALOX-2,MXC-3
                    IP=IP+1
                    INDXG=(IY-1)*MXC+IX
                    GSENDR(IP)=TEMPMCT(INDXG,NUMSENT)
                  END DO
                END DO
              ELSE IF (WHICHWAY.EQ.4) THEN
                DO IY=1,MYC
                  DO IX=IHALOX+1,IHALOX+3
                    IP=IP+1
                    INDXG=(IY-1)*MXC+IX
                    GSENDL(IP)=TEMPMCT(INDXG,NUMSENT)
                  END DO
                END DO
              END IF
              OFFSET=OFFSET+HALOSIZE
            END DO
          END DO
          DO INB=1,NNEIGH
            GSRC=IBLKAD(3*INB-1)-1
            WHICHWAY=IBLKAD(3*INB)
            IF (WHICHWAY.EQ.1) THEN
              CALL mpi_irecv (GRECVT,MSIZE,SWREAL,                      &
     &                        GSRC,TAGB,WAV_COMM_WORLD,TREQUEST,MyError)
            ELSE IF (WHICHWAY.EQ.2) THEN
              CALL mpi_irecv (GRECVB,MSIZE,SWREAL,                      &
     &                        GSRC,TAGT,WAV_COMM_WORLD,BREQUEST,MyError)
            ELSE IF (WHICHWAY.EQ.3) THEN
              CALL mpi_irecv (GRECVR,MSIZE,SWREAL,                      &
     &                        GSRC,TAGL,WAV_COMM_WORLD,RREQUEST,MyError)
            ELSE IF (WHICHWAY.EQ.4) THEN
              CALL mpi_irecv (GRECVL,MSIZE,SWREAL,                      &
     &                        GSRC,TAGR,WAV_COMM_WORLD,LREQUEST,MyError)
            END IF
          END DO
          DO INB=1,NNEIGH
            GDEST=IBLKAD(3*INB-1)-1
            WHICHWAY=IBLKAD(3*INB)
            IF (WHICHWAY.EQ.1) THEN
              CALL mpi_send (GSENDT,MSIZE,SWREAL,                       &
     &                       GDEST,TAGT,WAV_COMM_WORLD,MyError)
            ELSE IF (WHICHWAY.EQ.2) THEN
              CALL mpi_send (GSENDB,MSIZE,SWREAL,                       &
     &                       GDEST,TAGB,WAV_COMM_WORLD,MyError)
            ELSE IF (WHICHWAY.EQ.4) THEN
              CALL mpi_send (GSENDL,MSIZE,SWREAL,                       &
     &                       GDEST,TAGL,WAV_COMM_WORLD,MyError)
            ELSE IF (WHICHWAY.EQ.3) THEN
              CALL mpi_send (GSENDR,MSIZE,SWREAL,                       &
     &                       GDEST,TAGR,WAV_COMM_WORLD,MyError)
            END IF
          END DO
!
! Receive and unpack halo regions exchanged with adjacent tiles.
! [top, bot, right, left] = [1 2 3 4]
!
          DO INB=1,NNEIGH
            WHICHWAY=IBLKAD(3*INB)
            IF (WHICHWAY.EQ.1) THEN
              CALL mpi_wait (TREQUEST,status(1,1),MyError)
            ELSE IF (WHICHWAY.EQ.2) THEN
              CALL mpi_wait (BREQUEST,status(1,2),MyError)
            ELSE IF (WHICHWAY.EQ.3) THEN
              CALL mpi_wait (RREQUEST,status(1,3),MyError)
            ELSE IF (WHICHWAY.EQ.4) THEN
              CALL mpi_wait (LREQUEST,status(1,4),MyError)
            END IF
          END DO
!
          DO INB=1,NNEIGH
            OFFSET=0
            WHICHWAY=IBLKAD(3*INB)
            IF (WHICHWAY.EQ.1) THEN
              DO NUMSENT=1,NUMTRANSFER
                IP=OFFSET
                DO IY=MYC-2,MYC
                  DO IX=1,MXC
                    IP=IP+1
                    INDXG=(IY-1)*MXC+IX
                    TEMPMCT(INDXG,NUMSENT)=GRECVT(IP)
                  END DO
                END DO
                OFFSET=OFFSET+HALOSIZE
              END DO
            ELSE IF (WHICHWAY.EQ.2) THEN
              DO NUMSENT=1,NUMTRANSFER
                IP=OFFSET
                DO IY=1,IHALOY
                  DO IX=1,MXC
                    IP=IP+1
                    INDXG=(IY-1)*MXC+IX
                    TEMPMCT(INDXG,NUMSENT)=GRECVB(IP)
                  END DO
                END DO
                OFFSET=OFFSET+HALOSIZE
              END DO
            ELSE IF (WHICHWAY.EQ.3) THEN
              DO NUMSENT=1,NUMTRANSFER
                IP=OFFSET
                DO IY=1,MYC
                  DO IX=MXC-2,MXC
                    IP=IP+1
                    INDXG=(IY-1)*MXC+IX
                    TEMPMCT(INDXG,NUMSENT)=GRECVR(IP)
                  END DO
                END DO
                OFFSET=OFFSET+HALOSIZE
              END DO
            ELSE IF (WHICHWAY.EQ.4) THEN
              DO NUMSENT=1,NUMTRANSFER
                IP=OFFSET
                DO IY=1,MYC
                  DO IX=1,IHALOX
                    IP=IP+1
                    INDXG=(IY-1)*MXC+IX
                    TEMPMCT(INDXG,NUMSENT)=GRECVL(IP)
                  END DO
                END DO
                OFFSET=OFFSET+HALOSIZE
              END DO
            END IF
          END DO
          IF (MXCGL.GT.MYCGL) THEN
            deallocate (GRECVR,GRECVL,GSENDR,GSENDL)
          ELSE
            deallocate (GRECVT,GRECVB,GSENDT,GSENDB)
          END IF
        END IF
!
! Finally insert the full (MXC*MYC) TEMPMCT array into the SWAN
! array for DEPTH and computational array COMPDA. Only insert
! active (wet points) using array KGRPNT.
!
!
!  Insert depth into SWAN array.
!
        IP=0
        DO IY = MYF,MYL
          DO IX = MXF,MXL
            IP=IP+1
            INDX=KGRPNT(IX-MXF+1,IY-MYF+1)
            IF (INDX.GT.1) THEN
              DEPTH(IX,IY)=TEMPMCT(IP,1)
            END IF
          END DO
        END DO
!
! Move values at 'present' time level 2 to 'old' time level 1.
! MCGRD = MXC*MYC+1-#masked cells.
! MXC = # cells x-dir in this tile including halox.
! MYC = # cells y-dir in this tile including haloy.
! COMPDA has only active wet points + 1.
!
        DO INDX = 2, MCGRD
          COMPDA(INDX,JWLV1)=COMPDA(INDX,JWLV2)
          COMPDA(INDX,JVX1) =COMPDA(INDX,JVX2)
          COMPDA(INDX,JVY1) =COMPDA(INDX,JVY2)
          COMPDA(INDX,JFRC3)=COMPDA(INDX,JFRC2)
        END DO
!
! Insert water level, velx, and vely into SWAN arrays.
!
        IP=0
        DO IY=1,MYC
          DO IX=1,MXC
            IP=IP+1
            INDX = KGRPNT(IX,IY)
            IF (INDX.GT.1) THEN
              COMPDA(INDX,JWLV2)=TEMPMCT(IP,2)
              COMPDA(INDX,JVX2)=TEMPMCT(IP,3)
              COMPDA(INDX,JVY2)=TEMPMCT(IP,4)
              COMPDA(INDX,JFRC2)=REAL(TEMPMCT(IP,5))
# ifdef ATM_COUPLING
              COMPDA(INDX,JWX2)=TEMPMCT(IP,6)
              COMPDA(INDX,JWY2)=TEMPMCT(IP,7)
# endif
            END IF
          END DO
        END DO
!
        deallocate (TEMPMCT)
      END IF
      deallocate (avdata, points)
!
 10   FORMAT (' WAV2OCN_COUPLING - error while sending fields to ',     &
     &        a,i4)
 20   FORMAT (' WAV2OCN_COUPLING - error while receiving fields from ', &
     &        a,i4)
 30   FORMAT (6x,'WAV2OCN   - (', i2.2, ') imported and (', i2.2,       &
     &        ') exported fields,', t62, 't = ', a,/, 16x,              &
     &        '- SWAN coupling exchanges wait clock (s):',/, 19x,       &
     &        '(Recv= ', 1p,e14.8,0p, ' Send= ', 1p,e14.8,0p,')')

      RETURN
      END SUBROUTINE WAV2OCN_COUPLING

      SUBROUTINE FINALIZE_WAV2OCN_COUPLING
!
!=======================================================================
!                                                                    ===
!  This routines terminates execution during coupling error.         ===
!                                                                    ===
!=======================================================================
!
!  Local variable declarations.
!
      integer :: MyError
!
!-----------------------------------------------------------------------
!  Deallocate MCT environment.
!-----------------------------------------------------------------------
!
      CALL Router_clean (SWANtoROMS, MyError)
      CALL AttrVect_clean (wav2ocn_AV, MyError)
# ifdef WRF_COUPLING
      CALL Router_clean (WRFtoSWAN, MyError)
      CALL AttrVect_clean (atm2wav_AV, MyError)
# endif
      CALL GlobalSegMap_clean (GSMapSWAN, MyError)

      END SUBROUTINE FINALIZE_WAV2OCN_COUPLING
#endif
      END MODULE WAVES_COUPLER_MOD
