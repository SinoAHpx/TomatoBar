import KeyboardShortcuts
import SwiftState
import SwiftUI

class TBTimer: ObservableObject {
    @AppStorage("stopAfterBreak") var stopAfterBreak = false
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar = true
    @AppStorage("enablePauseFeature") var enablePauseFeature = false
    @AppStorage("workIntervalLength") var workIntervalLength = 25
    @AppStorage("shortRestIntervalLength") var shortRestIntervalLength = 5
    @AppStorage("longRestIntervalLength") var longRestIntervalLength = 15
    @AppStorage("workIntervalsInSet") var workIntervalsInSet = 4
    @AppStorage("overrunTimeLimit") var overrunTimeLimit = -60.0

    private var stateMachine = TBStateMachine(state: .idle)
    public let player = TBPlayer()
    private var consecutiveWorkIntervals: Int = 0
    private var notificationCenter = TBNotificationCenter()
    private var finishTime: Date!
    private var timerFormatter = DateComponentsFormatter()
    private var pausedState: TBStateMachineStates?
    private var remainingTimeWhenPaused: TimeInterval = 0
    @Published var timeLeftString: String = ""
    @Published var timer: DispatchSourceTimer?
    @Published var isPaused: Bool = false

    @Published var currentGoal: String = ""
    @Published var isInTomatoCycle: Bool = false
    @Published var isDashMode: Bool = false
    private var tomatoCycleStarted: Bool = false
    private var isLongBreak: Bool = false
    private var tempDurationStackView: NSStackView?

    init() {
        /*
         * State diagram
         *
         *                 start/stop
         *       +--------------+-------------+
         *       |              |             |
         *       |  start/stop  |  timerFired |
         *       V    |         |    |        |
         * +--------+ |  +--------+  | +--------+
         * | idle   |--->| work   |--->| rest   |
         * +--------+    +--------+    +--------+
         *   A                  A        |    |
         *   |                  |        |    |
         *   |                  +--------+    |
         *   |  timerFired (!stopAfterBreak)  |
         *   |             skipRest           |
         *   |                                |
         *   +--------------------------------+
         *      timerFired (stopAfterBreak)
         *
         *              pause          pause
         *  work <-----------> paused <-----------> rest
         *
         */
        stateMachine.addRoutes(event: .startStop, transitions: [
            .idle => .work, .work => .idle, .rest => .idle, .paused => .idle,
        ])
        stateMachine.addRoutes(event: .pause, transitions: [
            .work => .paused, .rest => .paused, .paused => .work, .paused => .rest,
        ])
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .idle]) { _ in
            self.isDashMode
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.work => .rest]) { _ in
            !self.isDashMode
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .idle]) { _ in
            self.stopAfterBreak || (self.isLongBreak && self.isInTomatoCycle)
        }
        stateMachine.addRoutes(event: .timerFired, transitions: [.rest => .work]) { _ in
            !self.stopAfterBreak && !(self.isLongBreak && self.isInTomatoCycle)
        }
        stateMachine.addRoutes(event: .skipRest, transitions: [.rest => .work])

        /*
         * "Finish" handlers are called when time interval ended
         * "End"    handlers are called when time interval ended or was cancelled
         */
        stateMachine.addAnyHandler(.any => .work, handler: onWorkStart)
        stateMachine.addAnyHandler(.work => .rest, order: 0, handler: onWorkFinish)
        stateMachine.addAnyHandler(.work => .any, order: 1, handler: onWorkEnd)
        stateMachine.addAnyHandler(.any => .rest, handler: onRestStart)
        stateMachine.addAnyHandler(.rest => .work, handler: onRestFinish)
        stateMachine.addAnyHandler(.any => .idle, handler: onIdleStart)
        stateMachine.addAnyHandler(.any => .paused, handler: onPauseStart)
        stateMachine.addAnyHandler(.paused => .any, handler: onPauseEnd)
        stateMachine.addAnyHandler(.any => .any, handler: { ctx in
            logger.append(event: TBLogEventTransition(fromContext: ctx))
        })

        stateMachine.addErrorHandler { ctx in fatalError("state machine context: <\(ctx)>") }

        timerFormatter.unitsStyle = .positional
        timerFormatter.allowedUnits = [.minute, .second]
        timerFormatter.zeroFormattingBehavior = .pad

        KeyboardShortcuts.onKeyUp(for: .startStopTimer, action: startStop)
        KeyboardShortcuts.onKeyUp(for: .pauseTimer, action: pause)
        notificationCenter.setActionHandler(handler: onNotificationAction)

        let aem: NSAppleEventManager = NSAppleEventManager.shared()
        aem.setEventHandler(self,
                            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                            forEventClass: AEEventClass(kInternetEventClass),
                            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.forKeyword(AEKeyword(keyDirectObject))?.stringValue else {
            print("url handling error: cannot get url")
            return
        }
        let url = URL(string: urlString)
        guard url != nil,
              let scheme = url!.scheme,
              let host = url!.host else {
            print("url handling error: cannot parse url")
            return
        }
        guard scheme.caseInsensitiveCompare("tomatobar") == .orderedSame else {
            print("url handling error: unknown scheme \(scheme)")
            return
        }
        switch host.lowercased() {
        case "startstop":
            startStop()
        default:
            print("url handling error: unknown command \(host)")
            return
        }
    }

    func startStop() {
        if stateMachine.state == .idle && !isInTomatoCycle {
            showGoalInputDialog()
        } else {
            stateMachine <-! .startStop
        }
    }

    private var dashDuration: Int = 25

    func startWithGoal(_ goal: String, isDash: Bool = false, dashDuration: Int? = nil) {
        currentGoal = goal
        isInTomatoCycle = true
        tomatoCycleStarted = true
        isDashMode = isDash
        if let duration = dashDuration {
            self.dashDuration = duration
        }
        stateMachine <-! .startStop
    }

    private func showGoalInputDialog() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("TBTimer.goalInput.title", comment: "Enter your goal")
            alert.informativeText = NSLocalizedString("TBTimer.goalInput.message", comment: "What do you want to accomplish in this tomato session?")
            alert.alertStyle = .informational
            alert.addButton(withTitle: NSLocalizedString("TBTimer.goalInput.start", comment: "Start"))
            alert.addButton(withTitle: NSLocalizedString("TBTimer.goalInput.cancel", comment: "Cancel"))

            let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
            stackView.orientation = .vertical
            stackView.spacing = 8

            let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            inputTextField.placeholderString = NSLocalizedString("TBTimer.goalInput.placeholder", comment: "Enter your goal...")

            let dashCheckbox = NSButton(checkboxWithTitle: NSLocalizedString("TBTimer.goalInput.dashMode", comment: "Dash mode (single work session, no breaks)"), target: nil, action: nil)
            dashCheckbox.state = .off

            let durationStackView = NSStackView()
            durationStackView.orientation = .horizontal
            durationStackView.spacing = 8

            let durationLabel = NSTextField(labelWithString: NSLocalizedString("TBTimer.goalInput.duration", comment: "Duration (minutes):"))
            let durationTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
            durationTextField.placeholderString = "\(self.workIntervalLength)"
            durationTextField.stringValue = "\(self.workIntervalLength)"

            durationStackView.addArrangedSubview(durationLabel)
            durationStackView.addArrangedSubview(durationTextField)
            durationStackView.isHidden = true

            self.tempDurationStackView = durationStackView
            dashCheckbox.target = self
            dashCheckbox.action = #selector(self.dashCheckboxChanged(_:))

            stackView.addArrangedSubview(inputTextField)
            stackView.addArrangedSubview(dashCheckbox)
            stackView.addArrangedSubview(durationStackView)

            alert.accessoryView = stackView

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let goal = inputTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !goal.isEmpty {
                    let isDash = dashCheckbox.state == .on
                    var duration: Int? = nil
                    if isDash, let durationValue = Int(durationTextField.stringValue), durationValue > 0 {
                        duration = durationValue
                    }
                    self.startWithGoal(goal, isDash: isDash, dashDuration: duration)
                }
            }
            self.tempDurationStackView = nil
        }
    }

    @objc private func dashCheckboxChanged(_ sender: NSButton) {
        tempDurationStackView?.isHidden = sender.state == .off
    }

    func skipRest() {
        stateMachine <-! .skipRest
    }

    func pause() {
        stateMachine <-! .pause
    }

    #if DEBUG
    func skipSession() {
        stateMachine <-! .timerFired
    }
    #endif

    func updateTimeLeft() {
        timeLeftString = timerFormatter.string(from: Date(), to: finishTime)!
        if timer != nil, showTimerInMenuBar {
            TBStatusItem.shared.setTitle(title: timeLeftString)
        } else {
            TBStatusItem.shared.setTitle(title: nil)
        }
    }

    private func startTimer(seconds: Int) {
        finishTime = Date().addingTimeInterval(TimeInterval(seconds))

        let queue = DispatchQueue(label: "Timer")
        timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer!.schedule(deadline: .now(), repeating: .seconds(1), leeway: .never)
        timer!.setEventHandler(handler: onTimerTick)
        timer!.setCancelHandler(handler: onTimerCancel)
        timer!.resume()
    }

    private func stopTimer() {
        guard timer != nil else { return }
        timer!.cancel()
        timer = nil
    }

    private func onTimerTick() {
        /* Cannot publish updates from background thread */
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
            let timeLeft = finishTime.timeIntervalSince(Date())
            if timeLeft <= 0 {
                /*
                 Ticks can be missed during the machine sleep.
                 Stop the timer if it goes beyond an overrun time limit.
                 Only force stop during work intervals to prevent skipping rest periods.
                 */
                if timeLeft < overrunTimeLimit && stateMachine.state == .work {
                    stateMachine <-! .startStop
                } else {
                    stateMachine <-! .timerFired
                }
            }
        }
    }

    private func onTimerCancel() {
        DispatchQueue.main.async { [self] in
            updateTimeLeft()
        }
    }

    private func onNotificationAction(action: TBNotification.Action) {
        if action == .skipRest, stateMachine.state == .rest {
            skipRest()
        }
    }

    private func onWorkStart(context _: TBStateMachine.Context) {
        TBStatusItem.shared.setIcon(name: .work)
        player.playWindup()
        player.startTicking()
        let duration = isDashMode ? dashDuration : workIntervalLength
        startTimer(seconds: duration * 60)
    }

    private func onWorkFinish(context _: TBStateMachine.Context) {
        consecutiveWorkIntervals += 1
        player.playDing()
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onWorkFinish.title", comment: "Work session completed"),
            body: NSLocalizedString("TBTimer.onWorkFinish.body", comment: "Time for a break!"),
            category: .workFinished
        )
    }

    private func onWorkEnd(context _: TBStateMachine.Context) {
        player.stopTicking()
    }

    private func onRestStart(context _: TBStateMachine.Context) {
        var body = NSLocalizedString("TBTimer.onRestStart.short.body", comment: "Short break body")
        var length = shortRestIntervalLength
        var imgName = NSImage.Name.shortRest
        isLongBreak = false
        if consecutiveWorkIntervals >= workIntervalsInSet {
            body = NSLocalizedString("TBTimer.onRestStart.long.body", comment: "Long break body")
            length = longRestIntervalLength
            imgName = .longRest
            consecutiveWorkIntervals = 0
            isLongBreak = true
        }
        notificationCenter.send(
            title: NSLocalizedString("TBTimer.onRestStart.title", comment: "Time's up title"),
            body: body,
            category: .restStarted
        )
        TBStatusItem.shared.setIcon(name: imgName)
        startTimer(seconds: length * 60)
    }

    private func onRestFinish(context ctx: TBStateMachine.Context) {
        if ctx.event == .skipRest {
            return
        }

        if !isLongBreak || !isInTomatoCycle {
            notificationCenter.send(
                title: NSLocalizedString("TBTimer.onRestFinish.title", comment: "Break is over title"),
                body: NSLocalizedString("TBTimer.onRestFinish.body", comment: "Break is over body"),
                category: .restFinished
            )
        }
    }

    private func onIdleStart(context ctx: TBStateMachine.Context) {
        stopTimer()
        TBStatusItem.shared.setIcon(name: .idle)
        consecutiveWorkIntervals = 0

        if isDashMode && ctx.event == .timerFired {
            onDashCompleted()
            return
        }

        if isInTomatoCycle && tomatoCycleStarted && ctx.event == .startStop {
            onTomatoFailed()
            return
        }

        if isInTomatoCycle && isLongBreak && ctx.event == .timerFired {
            onTomatoCompleted()
        }
    }

    private func onTomatoCompleted() {
        guard isInTomatoCycle else { return }

        logger.append(event: TBLogEventTomatoCompleted(goal: currentGoal))

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("TBTimer.tomatoCompleted.title", comment: "Tomato Completed!")
            alert.informativeText = String(format: NSLocalizedString("TBTimer.tomatoCompleted.message", comment: "You completed: %@"), self.currentGoal)
            alert.alertStyle = .informational
            alert.addButton(withTitle: NSLocalizedString("TBTimer.tomatoCompleted.newGoal", comment: "New Goal"))
            alert.addButton(withTitle: NSLocalizedString("TBTimer.tomatoCompleted.continue", comment: "Continue"))
            alert.addButton(withTitle: NSLocalizedString("TBTimer.tomatoCompleted.rest", comment: "Rest"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.isInTomatoCycle = false
                self.tomatoCycleStarted = false
                self.currentGoal = ""
                self.showGoalInputDialog()
            } else if response == .alertSecondButtonReturn {
                self.tomatoCycleStarted = false
                self.startWithGoal(self.currentGoal)
            } else {
                self.isInTomatoCycle = false
                self.tomatoCycleStarted = false
                self.currentGoal = ""
            }
        }
    }

    private func onTomatoFailed() {
        guard isInTomatoCycle && tomatoCycleStarted else { return }

        logger.append(event: TBLogEventTomatoFailed(goal: currentGoal))

        isInTomatoCycle = false
        tomatoCycleStarted = false
        currentGoal = ""
    }

    private func onDashCompleted() {
        guard isDashMode else { return }

        logger.append(event: TBLogEventDashCompleted(goal: currentGoal))

        notificationCenter.send(
            title: NSLocalizedString("TBTimer.dashCompleted.title", comment: "Dash Completed!"),
            body: String(format: NSLocalizedString("TBTimer.dashCompleted.message", comment: "You completed: %@"), currentGoal),
            category: .restFinished
        )

        isInTomatoCycle = false
        tomatoCycleStarted = false
        currentGoal = ""
        isDashMode = false
        isLongBreak = false
    }

    private func onPauseStart(context ctx: TBStateMachine.Context) {
        pausedState = ctx.fromState
        remainingTimeWhenPaused = finishTime.timeIntervalSince(Date())
        stopTimer()
        player.stopTicking()
        TBStatusItem.shared.setIcon(name: .idle)
        isPaused = true
        timeLeftString = timerFormatter.string(from: remainingTimeWhenPaused)!
    }

    private func onPauseEnd(context ctx: TBStateMachine.Context) {
        isPaused = false
        if ctx.toState == .idle {
            return
        }
        if pausedState == .work {
            TBStatusItem.shared.setIcon(name: .work)
            player.startTicking()
        } else if pausedState == .rest {
            let imgName: NSImage.Name = consecutiveWorkIntervals == 0 ? .longRest : .shortRest
            TBStatusItem.shared.setIcon(name: imgName)
        }
        startTimer(seconds: Int(remainingTimeWhenPaused))
    }
}
