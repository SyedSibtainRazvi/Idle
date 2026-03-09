import XCTest
@testable import Idle

final class SessionManagementTests: XCTestCase {

  // MARK: - SessionItem identity

  func testSessionItemHasUniqueID() {
    let a = SessionItem(label: "A", title: "~", workingDirectory: "/tmp",
                        terminalView: GhosttyTerminalView())
    let b = SessionItem(label: "B", title: "~", workingDirectory: "/tmp",
                        terminalView: GhosttyTerminalView())
    XCTAssertNotEqual(a.id, b.id)
  }

  func testSessionItemDefaultState() {
    let s = SessionItem(label: "S1", title: "~", workingDirectory: "/Users/test",
                        terminalView: GhosttyTerminalView())
    XCTAssertEqual(s.label, "S1")
    XCTAssertEqual(s.processTitle, "")
    XCTAssertFalse(s.isRunning)
    XCTAssertNil(s.gitBranch)
    XCTAssertEqual(s.learningState.mode, .empty)
  }

  // MARK: - Closed sessions stack

  func testClosedSessionsStackFILO() {
    var closedSessions: [(label: String, workingDirectory: String)] = []
    closedSessions.append((label: "Session 1", workingDirectory: "/a"))
    closedSessions.append((label: "Session 2", workingDirectory: "/b"))
    closedSessions.append((label: "Session 3", workingDirectory: "/c"))

    let last = closedSessions.popLast()
    XCTAssertEqual(last?.label, "Session 3")
    XCTAssertEqual(last?.workingDirectory, "/c")
    XCTAssertEqual(closedSessions.count, 2)
  }

  func testClosedSessionsStackMaxSize() {
    var closedSessions: [(label: String, workingDirectory: String)] = []
    let maxClosedSessions = 10

    for i in 0..<15 {
      closedSessions.append((label: "Session \(i)", workingDirectory: "/dir\(i)"))
      if closedSessions.count > maxClosedSessions {
        closedSessions.removeFirst()
      }
    }

    XCTAssertEqual(closedSessions.count, 10)
    // Oldest should be Session 5 (0-4 were evicted)
    XCTAssertEqual(closedSessions.first?.label, "Session 5")
    XCTAssertEqual(closedSessions.last?.label, "Session 14")
  }

  func testClosedSessionsStackEmptyPopReturnsNil() {
    var closedSessions: [(label: String, workingDirectory: String)] = []
    XCTAssertNil(closedSessions.popLast())
  }

  // MARK: - Index adjustment after tab close

  /// Simulates the index adjustment logic from closeSession
  private func adjustedIndex(activeIndex: Int, closedIndex: Int, sessionCount: Int) -> Int {
    if activeIndex >= sessionCount {
      return sessionCount - 1
    } else if activeIndex > closedIndex {
      return activeIndex - 1
    } else if activeIndex == closedIndex {
      return min(closedIndex, sessionCount - 1)
    } else {
      return activeIndex
    }
  }

  func testCloseTabToRight() {
    // Active is 1, close tab at 2, 3 sessions remain
    let newIndex = adjustedIndex(activeIndex: 1, closedIndex: 2, sessionCount: 2)
    XCTAssertEqual(newIndex, 1) // Active unchanged
  }

  func testCloseTabToLeft() {
    // Active is 2, close tab at 0, 2 sessions remain
    let newIndex = adjustedIndex(activeIndex: 2, closedIndex: 0, sessionCount: 2)
    XCTAssertEqual(newIndex, 1) // Active shifts left
  }

  func testCloseActiveTab() {
    // Active is 1, close tab at 1, 2 sessions remain
    let newIndex = adjustedIndex(activeIndex: 1, closedIndex: 1, sessionCount: 2)
    XCTAssertEqual(newIndex, 1) // Next tab takes over
  }

  func testCloseActiveLastTab() {
    // Active is 2 (last), close it, 2 sessions remain
    let newIndex = adjustedIndex(activeIndex: 2, closedIndex: 2, sessionCount: 2)
    XCTAssertEqual(newIndex, 1) // Clamps to new last
  }

  // MARK: - Session identity vs index comparison

  func testSessionIdentityPreservedAfterIndexShift() {
    // Simulate: 3 sessions [A, B, C], active=2 (C), close tab 0 (A)
    var sessions = [
      makeSession(label: "A"),
      makeSession(label: "B"),
      makeSession(label: "C"),
    ]
    let activeID = sessions[2].id  // C's identity

    sessions.remove(at: 0)  // Remove A, array is now [B, C]

    // New index for C is 1, but identity should match
    let newIndex = 1
    XCTAssertEqual(sessions[newIndex].id, activeID)
  }

  func testSessionIdentityChangesWhenActiveTabClosed() {
    var sessions = [
      makeSession(label: "A"),
      makeSession(label: "B"),
      makeSession(label: "C"),
    ]
    let activeID = sessions[1].id  // B's identity

    sessions.remove(at: 1)  // Remove B, array is now [A, C]

    // The session at index 1 is now C, different identity
    XCTAssertNotEqual(sessions[1].id, activeID)
  }

  // MARK: - SearchBarView state

  func testSearchBarClearResetsState() {
    let searchBar = SearchBarView()
    searchBar.updateMatchCount(total: 5, selected: 2)
    XCTAssertEqual(searchBar.totalMatches, 5)

    searchBar.clear()
    XCTAssertEqual(searchBar.totalMatches, 0)
  }

  func testSearchBarUpdateMatchCount() {
    let searchBar = SearchBarView()
    searchBar.updateMatchCount(total: 10, selected: 3)
    XCTAssertEqual(searchBar.totalMatches, 10)
  }

  // MARK: - Helpers

  private func makeSession(label: String) -> SessionItem {
    SessionItem(label: label, title: "~", workingDirectory: "/tmp",
                terminalView: GhosttyTerminalView())
  }
}
