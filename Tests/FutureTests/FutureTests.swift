
import XCTest
@testable import Future

final class FutureTests: XCTestCase {
    func testResolveSynchronously() {
        let future: Future<Int, Error> = Future { resolve in
            resolve(.success(2))
        }

        let futureIsResolved = expectation(description: "Future is Resolved")

        future.done { value in
            try! XCTAssertEqual(value.get(), 2)

            futureIsResolved.fulfill()
        }

        waitForExpectations(timeout: 0.1)
    }

    func testResolveAsynchronously() {
        let future: Future<Int, Error> = Future { resolve in
            DispatchQueue.main.async {
                resolve(.success(2))
            }
        }

        let futureIsResolved = expectation(description: "Future is Resolved")

        future.done { value in
            try! XCTAssertEqual(value.get(), 2)

            futureIsResolved.fulfill()
        }

        waitForExpectations(timeout: 0.1)
    }

    func testFutureIsCold() {
        let futureHasNotStarted = expectation(description: "Future has not started")
        futureHasNotStarted.isInverted = true

        let futureHasStarted = expectation(description: "Future has started")

        let future: Future<Int, Error> = Future { resolve in
            futureHasNotStarted.fulfill()
            futureHasStarted.fulfill()

            resolve(.success(2))
        }

        let x = future
            .map {
                $0 + 2
            }
            .flatMap {
                Future(value: $0 + 2)
            }

        wait(for: [ futureHasNotStarted ], timeout: 0.1)

        let futureIsResolved = expectation(description: "Future is Resolved")

        x.done { result in
            try! XCTAssertEqual(result.get(), 6)

            futureIsResolved.fulfill()
        }

        waitForExpectations(timeout: 0.1)
    }
}
