! Vitesse Timer Class GCR 26Aug2013
! (c) 2013 Geoffrey C. Robinson.  vitessegr AT gmail DOT com
! Released under the MIT License - see LICENSE.
  MEMBER

  Include('VitTimer.inc'),ONCE

  Map
  End

VitTimer.Start                Procedure()
 CODE
    loop                              ! the date read again after the time: midnight between the
      self.StartDate = today()        !   two reads would pair the old day with the new day's time
      self.StartTime = clock()
      if today() = self.StartDate then break.
    end
    self.EndDate = 0
    self.EndTime = 0

VitTimer.Stop                 Procedure()
 CODE
    loop ! as in Start: the date again after the time
      self.EndDate = today()
      self.EndTime = clock()
      if today() = self.EndDate then break.
    end

VitTimer.Duration             Procedure() !,STRING

L:Days     LONG,AUTO
L:Hours    LONG,AUTO
L:Mins     LONG,AUTO

L:Duration LONG,AUTO

  CODE
    if ~self.StartTime then return('????').

    if ~self.EndTime then self.Stop().

    L:Days = self.EndDate - self.StartDate
    L:Duration = self.EndTime - self.StartTime

    LOOP while L:Duration < 0
        L:Duration += 8640000         ! add a day
        L:Days -= 1
    end

    if ~L:Days and ~L:Duration        ! GCR 25Feb2014
        return('Too fast to measure')
    end

    ! assignment to LONG truncates - do NOT wrap these lines in int(). They are correct exactly as they are.
    L:Hours    = L:Duration / 360000
    L:Duration %= 360000              ! keep remainder after removing hours
    L:Mins     = L:Duration / 6000
    L:Duration %= 6000                ! keep remainder after removing minutes

    Return( clip(choose(~L:Days, '',L:Days  & ' day'    & choose(L:Days  < 2, ' ', 's ')) & |
                 choose(~L:Hours,'',L:Hours & ' hour'   & choose(L:Hours < 2, ' ', 's ')) & |
                 choose(~L:Mins, '',L:Mins  & ' minute' & choose(L:Mins  < 2, ' ', 's ')) & |
                 choose(~L:Duration, '',L:Duration/100  & ' second' & choose(L:Duration = 100, '' , 's'))))

