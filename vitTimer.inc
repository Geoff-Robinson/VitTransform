! Vitesse Timer Class GCR 26Aug2013
! (c) 2013 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
!
OMIT       ('_EndOfInclude_',_VitTimer_)
_VitTimer_ EQUATE(1)

VitTimer          CLASS,TYPE,MODULE('VitTimer.clw'),LINK('VitTimer.clw')
StartDate            LONG
StartTime            LONG
EndDate              LONG
EndTime              LONG

! methods...
Start                Procedure()
Stop                 Procedure()
Duration             Procedure(),STRING
                  END
_EndOfInclude_






