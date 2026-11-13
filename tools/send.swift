import Foundation
DistributedNotificationCenter.default().postNotificationName(Notification.Name("station.debug"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
