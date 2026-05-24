tell application "Calendar"
  set now to current date
  set nowTime to time of now
  set todayStart to current date
  set time of todayStart to 0
  set endSearch to todayStart + 24 * 60 * 60
  set currentEvent to missing value
  set currentEndTime to 86400
  set nextEvent to missing value
  set nextStartTime to 86400
  set cal to calendar "Cary"
  repeat with evt in (every event of cal whose end date >= now and start date < endSearch)
    set evtDate to start date of evt
    set evtStartTime to time of evtDate
    set evtDate to end date of evt
    set evtEndTime to time of evtDate
    -- For recurring events, check if start date is actually today
    set evtStartDate to start date of evt
    set evtDay to day of evtStartDate
    set evtMonth to month of evtStartDate as integer
    set evtYear to year of evtStartDate
    set evtWeekday to weekday of evtStartDate
    set todayDay to day of now
    set todayMonth to month of now as integer
    set todayYear to year of now
    set todayWeekday to weekday of now
    set isToday to (evtDay = todayDay and evtMonth = todayMonth and evtYear = todayYear and evtWeekday = todayWeekday)
    -- Skip all-day events, non-today events
    if evtStartTime = 0 and evtEndTime = 0 then
      -- skip all-day
    else if not isToday then
      -- skip events whose start date isn't actually today (recurring event bug)
    else if evtStartTime <= nowTime and evtEndTime >= nowTime then
      -- Currently happening
      if evtEndTime < currentEndTime then
        set currentEndTime to evtEndTime
        set currentEvent to evt
      end if
    else if evtStartTime > nowTime then
      -- Upcoming today
      if evtStartTime < nextStartTime then
        set nextStartTime to evtStartTime
        set nextEvent to evt
      end if
    end if
  end repeat
  set resultText to ""
  if currentEvent is not missing value then
    set evtSummary to my sanitize(summary of currentEvent)
    set resultText to "CURRENT|:|" & evtSummary & "|:|" & my fmtTime(start date of currentEvent) & "|:|" & my fmtTime(end date of currentEvent)
  end if
  if nextEvent is not missing value then
    set mins to ((nextStartTime - nowTime) div 60)
    set evtSummary to my sanitize(summary of nextEvent)
    set nextStr to (mins as text) & "|:|" & evtSummary & "|:|" & my fmtTime(start date of nextEvent) & "|:|" & my fmtTime(end date of nextEvent)
    if resultText is "" then
      set resultText to "NEXT|" & nextStr
    else
      set resultText to resultText & "|||" & nextStr
    end if
  end if
  return resultText
end tell

on sanitize(txt)
  set {oldTID, AppleScript's text item delimiters} to {AppleScript's text item delimiters, {return, linefeed, character id 10, character id 13}}
  set parts to text items of txt
  set AppleScript's text item delimiters to " "
  set cleaned to parts as text
  set AppleScript's text item delimiters to oldTID
  return cleaned
end sanitize

on fmtTime(d)
  set h to hours of d
  set m to minutes of d
  set ampm to "AM"
  if h >= 12 then set ampm to "PM"
  if h > 12 then set h to h - 12
  if h = 0 then set h to 12
  if m = 0 then
    return (h as text) & ampm
  else if m < 10 then
    return (h as text) & ":0" & m & ampm
  else
    return (h as text) & ":" & (m as text) & ampm
  end if
end fmtTime
