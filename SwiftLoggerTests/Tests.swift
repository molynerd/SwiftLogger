//
//  SwiftLoggerTests.swift
//  SwiftLoggerTests
//
//  Created by Nicholas Molyneux on 9/14/16.
//  Copyright © 2016 Nicholas Molyneux. All rights reserved.
//

import XCTest
@testable import SwiftLogger

class SwiftLoggerTests: XCTestCase {
    let log = SwiftLogger()
    var randomsUsed = [String]()
    
    override func tearDown() {
        log.purgeLogs(nil)
        super.tearDown()
    }
    
    /**Writes some simple logs, with single items*/
    func testWriteSingleLog() {
        for _ in 0...30 {
            self.log.info("write this to the log: \(self._rand())")
        }
        //force the logger to flush
        self.log.flushTailToDisk()
        //validate the log
        self._validate(randomsUsed)
    }
    
    func testWriteMultipleLog() {
        for _ in 0...30 {
            self.log.info("write these to the log", self._rand(), self._rand())
        }
        //force the logger to flush
        self.log.flushTailToDisk()
        //validate the log
        self._validate(randomsUsed)
    }
    
    //gets a random value, adds it to the randomsUsed and returns it
    private func _rand() -> String {
        let r = String(random())
        self.randomsUsed.append(r)
        return r
    }
    
    //validates that the random value used during execution actually showed up in the logs
    private func _validate(randomsUsed: [String]) {
        //get the logs that were written
        guard let logs = log.getLogs() else {
            XCTAssertNotNil(nil, "no log files were returned")
            return
        }
        
        //smash all the logs together
        let allLog = logs.values.joinWithSeparator("\n")
        
        //make sure the random numbers existed somewhere
        var randomsNotWritten = [String]()
        for str in randomsUsed {
            if !allLog.containsString(str) {
                randomsNotWritten.append(str)
            }
        }
        
        let randomsNotWrittenConcat = randomsNotWritten.joinWithSeparator(",")
        XCTAssertEqual(randomsNotWritten.count, 0, "numbers not writtern: \(randomsNotWrittenConcat)")
    }
}
