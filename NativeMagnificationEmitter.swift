import CoreGraphics
import Foundation

/// Private Quartz gesture fields used by Apple's WebKit test infrastructure.
/// AppKit converts this event shape into NSEventTypeMagnify with a continuous
/// magnification value and a began/changed/ended phase.
enum NativeMagnificationEventFactory {
    private static let gestureEventType = CGEventType(rawValue: 29)!
    private static let gestureHIDTypeField = CGEventField(rawValue: 110)!
    private static let gestureZoomValueField = CGEventField(rawValue: 113)!
    private static let gesturePhaseField = CGEventField(rawValue: 132)!
    private static let zoomHIDType: Int64 = 8

    static func makeEvent(
        phase: CompoundMagnificationPhase,
        amount: CGFloat,
        location: CGPoint
    ) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.type = gestureEventType
        event.location = location
        event.setIntegerValueField(gestureHIDTypeField, value: zoomHIDType)
        event.setIntegerValueField(gesturePhaseField, value: gesturePhaseValue(phase))
        event.setDoubleValueField(gestureZoomValueField, value: Double(amount))
        return event
    }

    private static func gesturePhaseValue(_ phase: CompoundMagnificationPhase) -> Int64 {
        switch phase {
        case .began: return 1
        case .changed: return 2
        case .ended: return 4
        }
    }
}

final class NativeMagnificationEmitter {
    func post(_ magnification: CompoundMagnification, at location: CGPoint) {
        NativeMagnificationEventFactory.makeEvent(
            phase: magnification.phase,
            amount: magnification.amount,
            location: location
        )?.post(tap: .cghidEventTap)
    }
}
