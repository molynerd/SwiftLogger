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
    let logsToWrite = 1000
    var randomsUsed = [String]()
    
    override func tearDown() {
        log.purgeLogs(nil)
        super.tearDown()
    }
    
    /**Writes some simple logs, with single items*/
    func testWriteSingleLog() {
        for i in 0...logsToWrite {
            self.log.info("\(i) write this to the log: \(self._rand())")
        }
        //force the logger to flush
        self.log.flushTailToDisk()
        //validate the log
        self._validate(randomsUsed)
    }
    
    func testWriteMultipleLog() {
        for i in 0...logsToWrite {
            self.log.info("\(i) write these to the log", self._rand(), self._rand())
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
        //apparently these aren't in the correct for dictionaries, so we need to loop through the keys, sorted
        var allLog = ""
        for key in logs.keys.sort() {
            allLog += logs[key]!
            allLog += "\n"
        }
        
        //make sure the random numbers existed somewhere
        var randomsNotWritten = [String]()
        for str in randomsUsed {
            if !allLog.containsString(str) {
                randomsNotWritten.append(str)
            }
        }
        
        //make sure that the logs were written in order
        var lastNumber = -1
        var split = allLog.componentsSeparatedByString("\n")
        for i in 0..<split.count {
            let current = split[i]
            guard let firstSpace = current.characters.indexOf(" ") else {
                continue
            }
            let charsUntilFirstSpace = current.substringToIndex(firstSpace)
            //skip the first 2 chars, since it should be this >"
            let trimmed = charsUntilFirstSpace.substringFromIndex(charsUntilFirstSpace.startIndex.advancedBy(2))
            guard let num = Int(trimmed) else {
                continue
            }
            XCTAssertEqual(lastNumber + 1, num, "logs written out of order: preceding \(lastNumber + 1), current \(num)")
            lastNumber += 1
        }
        
        let randomsNotWrittenConcat = randomsNotWritten.joinWithSeparator(",")
        XCTAssertEqual(randomsNotWritten.count, 0, "numbers not writtern: \(randomsNotWrittenConcat)")
    }
}
