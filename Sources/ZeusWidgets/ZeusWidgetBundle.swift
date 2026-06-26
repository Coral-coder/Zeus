import WidgetKit
import SwiftUI

@main
struct ZeusWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        ControlPanelWidget()
        if #available(iOS 18.0, *) {
            StartControl()
            LockControl()
        }
    }
}
