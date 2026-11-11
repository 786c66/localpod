import XCTest
@testable import LocalPodKit

final class ImportNotificationPolicyTests: XCTestCase {
    private func summary(
        collectionName: String = "测试合集",
        imported: Int = 0,
        relinked: Int = 0,
        failed: Int = 0,
        cancelled: Bool = false,
        firstIssueMessage: String? = nil
    ) -> ImportNotificationSummary {
        ImportNotificationSummary(
            collectionName: collectionName,
            importedCount: imported,
            relinkedCount: relinked,
            failedCount: failed,
            cancelled: cancelled,
            firstIssueMessage: firstIssueMessage
        )
    }

    private func decision(
        summary: ImportNotificationSummary?,
        errorMessage: String? = nil,
        isAppActive: Bool = false,
        isEnabled: Bool = true
    ) -> ImportNotificationDecision {
        ImportNotificationPolicy.decision(
            summary: summary,
            errorMessage: errorMessage,
            isAppActive: isAppActive,
            isEnabled: isEnabled
        )
    }

    func testDisabledSettingNeverNotifies() {
        XCTAssertEqual(
            decision(summary: summary(imported: 3), isEnabled: false),
            .none
        )
        XCTAssertEqual(
            decision(summary: nil, errorMessage: "boom", isEnabled: false),
            .none
        )
    }

    func testForegroundAppSuppressesSuccessAndFailure() {
        XCTAssertEqual(
            decision(summary: summary(imported: 3), isAppActive: true),
            .none
        )
        XCTAssertEqual(
            decision(summary: nil, errorMessage: "boom", isAppActive: true),
            .none
        )
        XCTAssertEqual(
            decision(
                summary: summary(failed: 2),
                isAppActive: true
            ),
            .none
        )
    }

    func testSuccessNotifiesWithImportedCountAndCollection() {
        XCTAssertEqual(
            decision(summary: summary(collectionName: "音乐", imported: 3)),
            .notifySuccess(importedCount: 3, relinkedCount: 0, collectionName: "音乐")
        )
    }

    func testRelinkedFilesCountAsSuccess() {
        XCTAssertEqual(
            decision(summary: summary(collectionName: "播客", relinked: 2)),
            .notifySuccess(importedCount: 0, relinkedCount: 2, collectionName: "播客")
        )
    }

    func testPartialSuccessPrefersSuccessDecision() {
        // Some files failed, but the user still gained two new items. The
        // import screen/report covers the failures.
        XCTAssertEqual(
            decision(summary: summary(imported: 2, failed: 5)),
            .notifySuccess(importedCount: 2, relinkedCount: 0, collectionName: "测试合集")
        )
    }

    func testZeroImportWithFailuresBecomesFailureWithFirstIssue() {
        XCTAssertEqual(
            decision(
                summary: summary(failed: 1, firstIssueMessage: "文件已损坏")
            ),
            .notifyFailure(message: "文件已损坏")
        )
    }

    func testZeroImportWithoutFailuresProducesNoNotification() {
        // Everything was a duplicate or unsupported: nothing new arrived and
        // nothing failed, so there is nothing actionable to say.
        XCTAssertEqual(decision(summary: summary()), .none)
    }

    func testHardErrorNotifiesFailure() {
        XCTAssertEqual(
            decision(summary: nil, errorMessage: "存储空间不足"),
            .notifyFailure(message: "存储空间不足")
        )
    }

    func testHardErrorTakesPriorityOverSummary() {
        XCTAssertEqual(
            decision(summary: summary(imported: 0), errorMessage: "磁盘写入失败"),
            .notifyFailure(message: "磁盘写入失败")
        )
    }

    func testCancelledRunProducesNoNotification() {
        XCTAssertEqual(
            decision(summary: summary(imported: 4, cancelled: true)),
            .none
        )
        XCTAssertEqual(
            decision(summary: summary(failed: 1, cancelled: true)),
            .none
        )
        // The coordinator's CancellationError path has neither summary nor
        // error message.
        XCTAssertEqual(decision(summary: nil), .none)
    }

    func testBlankMessagesAreNormalized() {
        XCTAssertEqual(
            decision(summary: nil, errorMessage: "   \n"),
            .none
        )
        XCTAssertEqual(
            decision(summary: summary(failed: 1, firstIssueMessage: "  ")),
            .notifyFailure(message: nil)
        )
    }
}
