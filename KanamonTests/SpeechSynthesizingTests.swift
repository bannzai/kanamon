import Foundation
import XCTest

@testable import Kanamon

/// `JapaneseSpeechSynthesizer` を並行して呼んでも、待たせた呼び出し元が残らないことを確かめる。
///
/// simulator では音声が鳴らず読み終わりの通知が届かないことがあるため、時間切れの保険で返る場合も含めて見る。
final class SpeechSynthesizingTests: XCTestCase {
  /// 待ちが残った時にテストごと止まらないための上限。1 文字の時間切れの保険 (1.7 秒) より十分長くする
  private static let returnTimeoutSeconds: TimeInterval = 10
  /// 中断で返ったことを、時間切れの保険 (20 文字で 15 秒) で返った場合と見分けるための上限
  private static let stopReturnSeconds: TimeInterval = 5
  /// 1 音をはっきり読ませる `YomiRenshuModel` と同じ速さ。
  private static let rate: Float = 0.4

  func testConcurrentSpeakCallsBothReturn() async {
    let synthesizer = JapaneseSpeechSynthesizer()
    let bothReturned = expectation(description: "同時に呼んだ speak が 2 つとも返る")

    Task {
      await withTaskGroup(of: Void.self) { group in
        group.addTask { await synthesizer.speak(text: "ア", rate: Self.rate) }
        group.addTask { await synthesizer.speak(text: "ア", rate: Self.rate) }
      }
      bothReturned.fulfill()
    }

    await fulfillment(of: [bothReturned], timeout: Self.returnTimeoutSeconds)
  }

  /// 発話中に中断したら、時間切れの保険を待たずに speak が返る。
  func testStopReturnsWaitingSpeakBeforeTimeout() async {
    let synthesizer = JapaneseSpeechSynthesizer()
    // 時間切れの保険が 15 秒になる長さ。中断で返ったのか保険で返ったのかを所要時間で見分けられるようにする
    let text = String(repeating: "ア", count: 20)
    let startedDate = Date()

    await withTaskGroup(of: Void.self) { group in
      group.addTask { await synthesizer.speak(text: text, rate: Self.rate) }
      group.addTask {
        // speak が発話を登録し終える前の中断は空振りするため、speak が返るまで呼び直す
        while !Task.isCancelled {
          synthesizer.stop()
          try? await Task.sleep(for: .milliseconds(20))
        }
      }

      // 中断を呼び直す側は取り消されるまで終わらないため、先に終わるのは speak
      await group.next()
      group.cancelAll()
    }

    XCTAssertLessThan(Date().timeIntervalSince(startedDate), Self.stopReturnSeconds)
  }
}
