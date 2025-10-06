import SwiftState

typealias TBStateMachine = StateMachine<TBStateMachineStates, TBStateMachineEvents>

enum TBStateMachineEvents: EventType {
    case startStop, timerFired, skipRest, pause
}

enum TBStateMachineStates: StateType {
    case idle, work, rest, paused
}
