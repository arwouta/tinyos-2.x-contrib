/*
 * Copyright (c) 2005-2006 Rincon Research Corporation
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the Rincon Research Corporation nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
 * RINCON RESEARCH OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE
 */

/**
 * T-Unit TinyOS Unit Testing
 *
 * After a "run" command is received from the computer, the testing process 
 * occurs in the following order on node 0 (the driving node):
 *
 *   1. SetUpOneTime - initializes this suite of tests
 *     (First Test:)
 *     2. SetUp - initializes an individual test
 *     3. TUnit.run() - run the test
 *     4. TearDown - tear down an individual test
 *
 *     (Second Test:)
 *     5. SetUp - initializes an individual test
 *     6. TUnit.run() - run the test
 *     7. TearDown - tear down an individual test
 *     
 *     ... etc.
 *
 *   8. TearDownOneTime - tears down the entire suite of tests
 *
 *
 * Secondary nodes see only SetUpOneTime(), and then no other commands.
 * This allows them to setup whatever is needed for the test, like the radio,
 * but prevents them from driving.  They can make assertions and also call
 * TUnit.done() to end the test, but they can't start a test.
 * 
 * Assertion results for each test are passed back to the computer for report 
 * generation
 *
 * The StatsQuery
 * 
 * @author David Moss
 */
 
#include "TestCase.h"
#include "AM.h"

module TUnitP {
  provides {
    interface TestCase[uint8_t testId];
    interface TestControl as SetUpOneTime @atmostonce();
    interface TestControl as SetUp @atmostonce();
    interface TestControl as TearDown @atmostonce();
    interface TestControl as TearDownOneTime @atmostonce();

    interface TUnitProcessing;
    interface StatsQuery;
  }
  
  uses {
    interface State as TUnitState;
    interface State as TestState;
    interface State as SendState;
    interface SplitControl as SerialSplitControl;
    
    async command am_addr_t amAddress(); 
  }
}

implementation {

  /** ID of the current test we're running */
  uint8_t currentTest;
  
  /**
   * TUnit State
   */
  enum {
    S_NOT_BOOTED,
    S_READY,
    S_RUNNING,
  };
  
  /** 
   * Test State
   */
  enum { 
    S_IDLE,
    S_SETUP_ONETIME,
    
    S_SETUP,
    S_RUN,
    S_TEARDOWN,
    
    S_TEARDOWN_ONETIME,
  };
  
  
  /***************** Prototypes ****************/
  task void waitForSendDone();
  
  void setUpOneTimeDone();
  void setUpDone();
  void runDone();
  void tearDownDone();
  void tearDownOneTimeDone();
  void attemptTest();
  
  /***************** SerialSplitControl Events ****************/
  /**
   * SerialSplitControl is started inside of Link_TUnitProcessingP
   */
  event void SerialSplitControl.startDone(error_t error) {
    if(call TUnitState.getState() == S_NOT_BOOTED) {
      call TUnitState.forceState(S_READY);
      
      if(call amAddress() != 0) {
        // This is not the base node driving the test.
        // SetUpOneTime and don't touch anything else, unless we get notified
        // that the test is complete.  Then we let the computer know
        // and shut off.
         call TUnitState.forceState(S_RUNNING);
         call TestState.forceState(S_SETUP_ONETIME);
         signal SetUpOneTime.run();
      }
    }
  }
  
  event void SerialSplitControl.stopDone(error_t error) {
  }
  
  /***************** TUnitProcessing Commands ****************/
  command void TUnitProcessing.run() {
    if(call TUnitState.getState() == S_READY) {
      call TUnitState.forceState(S_RUNNING);
      call TestState.forceState(S_SETUP_ONETIME);
      currentTest = 0;
      signal SetUpOneTime.run();
      // Execution continues when setUpOneTimeDone()
    }
  }
  
  command void TUnitProcessing.ping() {
    signal TUnitProcessing.pong();
  }
  
  /***************** TestCase Commands ****************/
  command void TestCase.done[uint8_t testId]() {
    runDone();
  }

  /***************** Assertions ****************/
  void assertEqualsFailed(char *failMsg, uint32_t expected, uint32_t actual) __attribute__((noinline)) @C() @spontaneous() {
    if(!call TUnitState.isIdle()) {
      signal TUnitProcessing.testEqualsFailed(currentTest, failMsg, expected, actual);
    }
  }
  
  void assertNotEqualsFailed(char *failMsg, uint32_t actual) __attribute__((noinline)) @C() @spontaneous() {
    if(!call TUnitState.isIdle()) {
      signal TUnitProcessing.testNotEqualsFailed(currentTest, failMsg, actual);
    }
  }
  
    void assertResultIsBelowFailed(char *failMsg, uint32_t upperbound, uint32_t actual) __attribute__((noinline)) @C() @spontaneous() {
    if(!call TUnitState.isIdle()) {
      signal TUnitProcessing.testResultIsBelowFailed(currentTest, failMsg, upperbound, actual);
    }
  }
  
  void assertResultIsAboveFailed(char *failMsg, uint32_t lowerbound, uint32_t actual) __attribute__((noinline)) @C() @spontaneous() {
    if(!call TUnitState.isIdle()) {
      signal TUnitProcessing.testResultIsAboveFailed(currentTest, failMsg, lowerbound, actual);
    }
  }
  
  void assertSuccess() __attribute__((noinline)) @C() @spontaneous() {
    if(!call TUnitState.isIdle()) {
      signal TUnitProcessing.testSuccess(currentTest);
    }
  }
  

  void assertFail(char *failMsg) __attribute__((noinline)) @C() @spontaneous() {
    if(!call TUnitState.isIdle()) {
      signal TUnitProcessing.testFailed(currentTest, failMsg);
    }
  }
  
  /***************** Setup and Teardown Commands ****************/
  command void SetUpOneTime.done() {
    setUpOneTimeDone();
  }
  
  command void SetUp.done() {
    setUpDone();
  }

  command void TearDown.done() {
    tearDownDone();
  }
  
  command void TearDownOneTime.done() {
    tearDownOneTimeDone();
  }
  
  
  /***************** Funtions ****************/
  /**
   * Node 0, which drives the test, is allowed to attempt the test.
   * All other nodes run setUpOneTime() to initiate the entire test suite,
   * and then don't do anything else.  Those other nodes can certainly make
   * assertions and call TUnit.done() to end the test on the computer, but
   * they are not allowed to drive.  That's why the code below shows any node
   * that is not node 0 sitting in the S_RUN state immediately after test
   * setup.
   */
  void setUpOneTimeDone() {
    if(call TestState.getState() == S_SETUP_ONETIME) {
      call TestState.toIdle();
      if(call amAddress() != 0) {
        call TestState.forceState(S_RUN);
        
      } else {
        attemptTest();
      }
    }
  }
  
  void setUpDone() {
    if(call TestState.getState() == S_SETUP) {
      call TestState.forceState(S_RUN);
      signal TestCase.run[currentTest]();
      // Execution continues when runDone()
    }
  }
  
  void runDone() {
    if(call TestState.getState() == S_RUN) {
      call TestState.forceState(S_TEARDOWN);
      signal TearDown.run();
      // Execution continues when tearDownDone()
    }
  }
  
  void tearDownDone() {
    if(call TestState.getState() == S_TEARDOWN) {
      call TestState.toIdle();
      post waitForSendDone();
      // Wait for all communication to exfil before running the next test
    }
  }
  
  void tearDownOneTimeDone() {
    call TUnitState.forceState(S_READY);
    call TestState.toIdle();
    signal TUnitProcessing.allDone();
    // Execution stops.
  }
  
  void attemptTest() {
    if(currentTest < uniqueCount(UQ_TESTCASE)) {
      if(call TestState.requestState(S_SETUP) == SUCCESS) {
        // No tests being run right now, run the next test
        signal SetUp.run();
        // Execution continues when setUpDone()
      }
      
    } else {
      call TUnitState.forceState(S_TEARDOWN_ONETIME);
      signal TearDownOneTime.run();
      // Execution continues when tearDownOneTimeDone()
    }
  }
  
  /***************** Tasks ****************/
  task void waitForSendDone() {
    if(call SendState.isIdle() && signal StatsQuery.isIdle()) {
      // Comms available, run the next test
      currentTest++;
      attemptTest();
      
    } else {
      // Wait for comms to be available before running the next test
      post waitForSendDone();
    }
  }
    
  /***************** Defaults ****************/
  default event void SetUpOneTime.run() {
    setUpOneTimeDone();
  }
  
  default event void SetUp.run() {
    setUpDone();
  }
  
  default event void TestCase.run[uint8_t testId]() {
    runDone();
  }
  
  default event void TearDown.run() {
    tearDownDone();
  }
  
  default event void TearDownOneTime.run() {
    tearDownOneTimeDone();
  }
  
  /**
   * The Statistics component is not compiled in with the rest
   * of the system, use this default instead.
   */
  default event bool StatsQuery.isIdle() {
    return TRUE;
  }
}