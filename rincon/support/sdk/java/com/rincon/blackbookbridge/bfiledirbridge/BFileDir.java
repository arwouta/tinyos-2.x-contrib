package com.rincon.blackbookbridge.bfiledirbridge;

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
 * ARCHED ROCK OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE
 */


import java.io.IOException;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

import com.rincon.blackbookbridge.TinyosError;
import com.rincon.util.Util;

import net.tinyos.message.Message;
import net.tinyos.message.MessageListener;
import net.tinyos.message.MoteIF;
import net.tinyos.util.Messenger;

public class BFileDir extends Thread implements
    BFileDir_Commands, MessageListener {

  /** Communication with the mote */
  private static MoteIF comm;

  /** List of FileTransferEvents listeners */
  private static List listeners = new ArrayList();

  /** List of received messages */
  private List receivedMessages = new ArrayList();

  /** Message to send */
  private BFileDirMsg outMsg = new BFileDirMsg();

  /** Reply message received from the mote */
  private BFileDirMsg replyMsg = new BFileDirMsg();
  
  /** True if we sent a command and are waiting for a reply */
  private boolean waitingForReply;

  /**
   * Constructor
   * 
   */
  public BFileDir() {
    if (comm == null) {
      comm = new MoteIF((Messenger) null);
      comm.registerListener(new BFileDirMsg(), this);
      start();
    }
  }

  /**
   * Thread to handle events
   */
  public void run() {
    while (true) {
      if (!receivedMessages.isEmpty()) {
        BFileDirMsg inMsg = (BFileDirMsg) receivedMessages.get(0);

        if (inMsg != null) {

          switch(inMsg.get_short0()) {
          case BFileDir_Constants.EVENT_CORRUPTIONCHECKDONE:
            for(Iterator it = listeners.iterator(); it.hasNext(); ) {
              ((BFileDir_Events) it.next()).bFileDir_corruptionCheckDone(Util.dataToFilename(inMsg.get_fileName()), inMsg.get_bool0() == 1, new TinyosError(inMsg.get_short1()));
            }
            break;          
            
          case BFileDir_Constants.EVENT_EXISTSCHECKDONE:
            for(Iterator it = listeners.iterator(); it.hasNext(); ) {
              ((BFileDir_Events) it.next()).bFileDir_existsCheckDone(Util.dataToFilename(inMsg.get_fileName()),inMsg.get_bool0() == 1, new TinyosError(inMsg.get_short1()));
            }
            break;          
            
          case BFileDir_Constants.EVENT_NEXTFILE:
            for(Iterator it = listeners.iterator(); it.hasNext(); ) {
              ((BFileDir_Events) it.next()).bFileDir_nextFile(Util.dataToFilename(inMsg.get_fileName()), new TinyosError(inMsg.get_short1()));
            }
            break;
          
          default:
          }

          receivedMessages.remove(inMsg);
        }
      }
    }
  }

  /**
   * Send a message
   * 
   * @param dest
   * @param m
   */
  private synchronized void send(int destination) {
    try {
      comm.send(destination, outMsg);
    } catch (IOException e) {
    }
  }

  /**
   * Add a BFileDir listener
   * 
   * @param listener
   */
  public void addListener(BFileDir_Events listener) {
    if (!listeners.contains(listener)) {
      listeners.add(listener);
    }
  }

  /**
   * Remove a BFileDir listener
   * 
   * @param listener
   */
  public void removeListener(BFileDir_Events listener) {
    listeners.remove(listener);
  }

  /**
   * Message received, handle replies immediately and handle events in a
   * thread
   */
  public synchronized void messageReceived(int to, Message m) {
    replyMsg = (BFileDirMsg) m;
    
    switch(replyMsg.get_short0()) {
    case BFileDir_Constants.REPLY_GETTOTALFILES:
      waitingForReply = false;
      notify();
      break;

    case BFileDir_Constants.REPLY_GETTOTALNODES:
      waitingForReply = false;
      notify();
      break;

    case BFileDir_Constants.REPLY_GETFREESPACE:
      waitingForReply = false;
      notify();
      break;

    case BFileDir_Constants.REPLY_CHECKEXISTS:
      waitingForReply = false;
      notify();
      break;

    case BFileDir_Constants.REPLY_READFIRST:
      waitingForReply = false;
      notify();
      break;

    case BFileDir_Constants.REPLY_READNEXT:
      waitingForReply = false;
      notify();
      break;

    case BFileDir_Constants.REPLY_GETRESERVEDLENGTH:
      waitingForReply = false;
      notify();
      break;

    case BFileDir_Constants.REPLY_GETDATALENGTH:
      waitingForReply = false;
      notify();
      break;

    case BFileDir_Constants.REPLY_CHECKCORRUPTION:
      waitingForReply = false;
      notify();
      break;


    default:
        // Events get handled by a separate thread
      receivedMessages.add(m);
    }
  }

  public synchronized short getTotalFiles(int destination) {
    waitingForReply = true;
    while(waitingForReply) {
      outMsg.set_short0(BFileDir_Constants.CMD_GETTOTALFILES);
      send(destination);
      try {
        wait(50);
      } catch (InterruptedException e) {
      }
    }
    return (short) replyMsg.get_short1();
  }

  public synchronized int getTotalNodes(int destination) {
    waitingForReply = true;
    while(waitingForReply) {
      outMsg.set_short0(BFileDir_Constants.CMD_GETTOTALNODES);
      send(destination);
      try {
        wait(50);
      } catch (InterruptedException e) {
      }
    }
    return (int) replyMsg.get_int0();
  }

  public synchronized long getFreeSpace(int destination) {
    waitingForReply = true;
    while(waitingForReply) {
      outMsg.set_short0(BFileDir_Constants.CMD_GETFREESPACE);
      send(destination);
      try {
        wait(50);
      } catch (InterruptedException e) {
      }
    }
    return (long) replyMsg.get_long0();
  }

  public synchronized TinyosError checkExists(int destination, String fileName) {
    waitingForReply = true;
    while(waitingForReply) {
      outMsg.set_short0(BFileDir_Constants.CMD_CHECKEXISTS);
      outMsg.set_fileName(Util.filenameToData(fileName, outMsg.get_fileName().length));
      send(destination);
      try {
        wait(50);
      } catch (InterruptedException e) {
      }
    }
    return new TinyosError(replyMsg.get_short1());
  }

  public synchronized TinyosError readFirst(int destination) {
    waitingForReply = true;
      outMsg.set_short0(BFileDir_Constants.CMD_READFIRST);
      send(destination);
      try {
        wait(500);
      } catch (InterruptedException e) {
      }
    return new TinyosError(replyMsg.get_short1());
  }

  public synchronized TinyosError readNext(int destination, String currentFilename) {
    waitingForReply = true;
      outMsg.set_short0(BFileDir_Constants.CMD_READNEXT);
      outMsg.set_fileName(Util.filenameToData(currentFilename, outMsg.get_fileName().length));
      send(destination);
      try {
        wait(500);
      } catch (InterruptedException e) {
      }
    return new TinyosError(replyMsg.get_short1());
  }

  public synchronized long getReservedLength(int destination, String fileName) {
    waitingForReply = true;
    while(waitingForReply) {
      outMsg.set_short0(BFileDir_Constants.CMD_GETRESERVEDLENGTH);
      outMsg.set_fileName(Util.filenameToData(fileName, outMsg.get_fileName().length));
      send(destination);
      try {
        wait(50);
      } catch (InterruptedException e) {
      }
    }
    return (long) replyMsg.get_long0();
  }

  public synchronized long getDataLength(int destination, String fileName) {
    waitingForReply = true;
    while(waitingForReply) {
      outMsg.set_short0(BFileDir_Constants.CMD_GETDATALENGTH);
      outMsg.set_fileName(Util.filenameToData(fileName, outMsg.get_fileName().length));
      send(destination);
      try {
        wait(50);
      } catch (InterruptedException e) {
      }
    }
    return (long) replyMsg.get_long0();
  }

  public synchronized TinyosError checkCorruption(int destination, String fileName) {
    waitingForReply = true;
    while(waitingForReply) {
      outMsg.set_short0(BFileDir_Constants.CMD_CHECKCORRUPTION);
      outMsg.set_fileName(Util.filenameToData(fileName, outMsg.get_fileName().length));
      send(destination);
      try {
        wait(50);
      } catch (InterruptedException e) {
      }
    }
    return new TinyosError(replyMsg.get_short1());
  }


}
