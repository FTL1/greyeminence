import SwiftUI

/// Brief hover copy: what it is, how to use it, why it exists.
/// Full text lives in Help → Controls and options (`CONTROL-REFERENCE.md`).
enum HelpTip: String {
    // Capture bar
    case watchForMeetings
    case liveAI
    case stopAll
    case waitingForCall
    case startRecording
    case recordButton
    case pauseRecording
    case stopRecording
    case recTimer
    case micMeter
    case systemMeter
    case segmentCount
    case linkCalendarEvent
    case screenCaptureIndicator
    case aiActivity

    // People bar
    case speakerChip
    case speakerChipHidden
    case heardChip
    case lockID
    case lockMe
    case addPerson
    case showAllSpeakers

    // Sidebar
    case sidebarCollapse
    case sidebarDashboard
    case sidebarAsk
    case sidebarFind
    case sidebarRecording
    case sidebarMeetings
    case sidebarArchive
    case sidebarInterviews
    case sidebarPeople
    case sidebarInsights
    case sidebarQuestions
    case sidebarTasks
    case sidebarSummaries
    case sidebarTopicMap
    case sidebarActivityLog
    case sidebarSettings
    case toolbarFind
    case toolbarInspector

    // Settings — General
    case settingsMyProfile
    case settingsDisplayName
    case settingsLaunchAtLogin
    case settingsMenuBar
    case settingsTextSize
    case settingsAutoMerge
    case settingsRetention
    case settingsStalled
    case settingsCheckUpdates

    // Settings — Audio / Calendar / AI / Screen / Dev
    case settingsInputDevice
    case settingsInputGain
    case settingsSystemAudio
    case settingsRetranscribe
    case settingsCalAutoDetect
    case settingsGraphConnect
    case settingsAIProvider
    case settingsAPIKey
    case settingsValidateKey
    case settingsTimeout
    case settingsScreenCapture
    case settingsScreenAutoDetect
    case settingsDevTools
    case settingsDevMode
    case settingsExportLog

    // Meeting header / library
    case meetingFind
    case meetingFindTranscript
    case meetingExportIntel
    case meetingUpgradeV3
    case meetingIndexSearch
    case libraryFindRegex
    case tasksMeetingsMenu
    case tasksAssignedMenu
    case tasksExport
    case tasksFind
    case tasksReset

    var tooltip: String {
        switch self {
        case .watchForMeetings:
            "Watches Zoom, Teams, Meet, Slack, Webex, FaceTime. Starts when that app holds the mic (Discord asks first). So you do not record this Mac all day."
        case .liveAI:
            "Rolling Grok/Claude notes while you record. Transcript still runs on this Mac. Turn off to skip API spend until Reanalyze."
        case .stopAll:
            "Stops capture, cancels Live AI, and turns Watch off. Nothing is recorded until you Watch or Record again."
        case .waitingForCall:
            "Idle wait — no mic or system audio yet. Recording starts when a meeting is detected, or you hit Record."
        case .startRecording:
            "Starts capture now. Independent of Watch. ⌘R. Use only where recording is lawful."
        case .recordButton:
            "Starts a new recording in this session. Same as Start Recording on the idle pane."
        case .pauseRecording:
            "Pauses capture without ending the meeting. Resume continues the same file and transcript."
        case .stopRecording:
            "Ends this recording and saves it. Auto-started calls also stop when the other app drops the mic."
        case .recTimer:
            "Elapsed time for this recording. Auto-stop at 4 hours; auto-started calls also stop after 20 minutes of silence."
        case .micMeter:
            "Your microphone level (you). If this is dead, grant Microphone to this copy of Grey Conseil."
        case .systemMeter:
            "Other people through the speakers (Teams/Zoom). Needs Screen & System Audio Recording."
        case .segmentCount:
            "How many transcript lines so far. Local transcription — not Live AI."
        case .linkCalendarEvent:
            "Attach a nearby calendar event for title, invitees, and the People bar. Change or unlink anytime."
        case .screenCaptureIndicator:
            "Shared-screen stills while you record. Enable in Settings → Screen Share. Nothing is captured without a share."
        case .aiActivity:
            "Live AI status: waiting, analyzing, or idle. Off means local transcript only."

        case .speakerChip:
            "This person. Click hide/show (grey = off). Right-click to assign, lock, or enroll a voice print."
        case .speakerChipHidden:
            "Hidden — their lines are off. Click to show them again."
        case .heardChip:
            "Unnamed voice (speaker-1…). Click to hide. Right-click → This is Pat to merge onto a person."
        case .lockID:
            "Lock keeps later lines on this person. Unlock if you need to retag."
        case .lockMe:
            "You are the Mac microphone. That seat stays locked."
        case .addPerson:
            "Pre-add someone you expect. Recording still starts as speaker-1 until you assign them."
        case .showAllSpeakers:
            "Turns every hidden person’s lines back on."

        case .sidebarCollapse:
            "Narrow or widen the sidebar. ⌘S. Icons keep their hover names when collapsed."
        case .sidebarDashboard:
            "Counts for this week, meetings, pending and stalled tasks. Cards are buttons."
        case .sidebarAsk:
            "AI search over transcripts. Needs an indexed meeting and an API key. Not the same as Find."
        case .sidebarFind:
            "Library search (⇧⌘F) in names, speakers, transcript, intel. ⌘F is this meeting only."
        case .sidebarRecording:
            "New Recording — start, watch, or resume a capture."
        case .sidebarMeetings:
            "Recent meetings (about three months), minus anything you filed to Archive."
        case .sidebarArchive:
            "The whole library. Export zip/PDF; file a meeting away from the recent list."
        case .sidebarInterviews:
            "Candidate interviews, rubrics, and scorecards. Separate from ordinary meetings."
        case .sidebarPeople:
            "Contacts, voice prints, and who appeared in meetings."
        case .sidebarInsights:
            "Intelligence across meetings — summaries, questions, tasks, topics."
        case .sidebarQuestions:
            "Follow-up questions rolled up from analyzed meetings."
        case .sidebarTasks:
            "Action items from analyzed meetings. Default: yours only."
        case .sidebarSummaries:
            "Meeting write-ups to browse and copy."
        case .sidebarTopicMap:
            "Topics as a map. Switch the list to People or Speakers."
        case .sidebarActivityLog:
            "Developer diagnostics. Shown when Developer tools are on."
        case .sidebarSettings:
            "AI keys, audio, calendar, screen share, profile. Also Grey Conseil → Settings."
        case .toolbarFind:
            "Library Find (⇧⌘F). ⌘F searches the open meeting."
        case .toolbarInspector:
            "Show or hide the Insights inspector beside a meeting."

        case .settingsMyProfile:
            "Who you are in transcripts and tasks. Pick the People contact that is you."
        case .settingsDisplayName:
            "Default name for the microphone seat instead of Me. Per-meeting rename can override."
        case .settingsLaunchAtLogin:
            "Opens Grey Conseil when you log in. Does not start recording by itself."
        case .settingsMenuBar:
            "Menu bar extra for Record / Stop without the main window."
        case .settingsTextSize:
            "App text size. Does not change transcript accuracy."
        case .settingsAutoMerge:
            "Joins consecutive lines from the same person after the meeting. Not while recording. Undo in transcript ⋯."
        case .settingsRetention:
            "Deletes old audio files only. Transcripts and meeting rows stay. Sweep at launch."
        case .settingsStalled:
            "Tasks older than this show as stalled. Does not complete or delete them."
        case .settingsCheckUpdates:
            "Fetches FTL1/grey-conseil releases. Never Matt’s Grey Eminence feed."

        case .settingsInputDevice:
            "Which mic is you. Built-in or a headset — this is the Me seat."
        case .settingsInputGain:
            "Mic boost before encoding. If you clip, turn it down."
        case .settingsSystemAudio:
            "Other people through the speakers. Needs Screen & System Audio Recording on Tahoe."
        case .settingsRetranscribe:
            "After stop, WhisperKit large-v3 upgrades the live transcript in the background."
        case .settingsCalAutoDetect:
            "Reads Mac calendars to name recordings and fill invitees. Local only."
        case .settingsGraphConnect:
            "Outlook/Teams calendar over Microsoft Graph. Paste the Entra client ID, then Connect."
        case .settingsAIProvider:
            "Live setting for the whole app — summaries, Live AI, Ask, Reanalyze. Switching here switches everything."
        case .settingsAPIKey:
            "Stored in Keychain on this Mac. Sent only to the provider you picked."
        case .settingsValidateKey:
            "Tests the key with a tiny request. Does not change which provider is active."
        case .settingsTimeout:
            "How long one analysis may run. Auto is ~4 min for Grok, ~2 for Claude. Raise it and Reanalyze once."
        case .settingsScreenCapture:
            "Stills of a shared window while you record. Off means no screenshots."
        case .settingsScreenAutoDetect:
            "Finds Teams/Discord share windows. Off: pick the window yourself on Record."
        case .settingsDevTools:
            "Shows Activity Log and extra transcript debug. Ordinary use can leave this off."
        case .settingsDevMode:
            "Verbose log of clicks, AI errors, capture. Export the JSON when something breaks."
        case .settingsExportLog:
            "Saves a JSON log with version and bundle ID. No need to copy a meeting transcript into it."

        case .meetingFind:
            "Search this meeting (⌘F). Tick Transcript to jump lines. ⌘G / ⇧⌘G walk hits."
        case .meetingFindTranscript:
            "Also highlight and jump matching lines in the transcript pane."
        case .meetingExportIntel:
            "Export or dossier this meeting’s stored intel. Does not invent facts."
        case .meetingUpgradeV3:
            "Re-transcribe this meeting with WhisperKit large-v3. Slow; more accurate."
        case .meetingIndexSearch:
            "Adds this transcript to Ask search. Use if Ask cannot find a meeting you know is here."
        case .libraryFindRegex:
            "Treat Find text as a regular expression. Example: cabinet.?count"
        case .tasksMeetingsMenu:
            "Which meetings to pull tasks from. Default is every analyzed meeting."
        case .tasksAssignedMenu:
            "Whose tasks to show. Default is only yours."
        case .tasksExport:
            "Copy the visible list, or save CSV, Excel, RTF, or PDF."
        case .tasksFind:
            "Search the current filters. If meetings still need analysis, you will be asked first."
        case .tasksReset:
            "Back to analyzed meetings and my tasks."
        }
    }
}

extension View {
    func helpTip(_ tip: HelpTip) -> some View {
        help(tip.tooltip)
    }
}
