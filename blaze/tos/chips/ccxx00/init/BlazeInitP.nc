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
 * Due to hardware design and battery considerations, we can only have one radio
 * on at a time.  BlazeInit will protect this rule by storing and checking
 * the enabled radio's ID.
 *
 * Also, some platforms might support the Power pin, which controls a FET
 * switch that turns off the radio.  For platforms that don't have a Power pin,
 * the radio should go into a deep sleep mode.  On platforms that do have a 
 * power pin, the radio will enter deep sleep then turn off completely.
 * 
 * @author Jared Hill 
 * @author David Moss
 */
 
#include "Blaze.h"
#include "BlazeInit.h"

module BlazeInitP {

  provides {
    interface Init;
    interface SplitControl[ radio_id_t id ];
    interface BlazePower[ radio_id_t id ];
    interface BlazeCommit[ radio_id_t id ];
  }
  
  uses {
    interface SplitControl as ReceiveSplitControl[radio_id_t radioId];
    
    interface Resource as ResetResource;
    interface Resource as DeepSleepResource;
     
    interface GeneralIO as Csn[ radio_id_t id ];
    interface GeneralIO as Gdo0_io[ radio_id_t id ];
    interface GeneralIO as Gdo2_io[ radio_id_t id ];
    interface GeneralIO as Power[ radio_id_t id ];
    interface GpioInterrupt as Gdo0_int[ radio_id_t id ];
    interface GpioInterrupt as Gdo2_int[ radio_id_t id ];
    interface RadioReset[ radio_id_t id ];
    
    interface BlazeRegSettings[ radio_id_t id ];
    interface RadioStatus;
    
    interface RadioInit as RadioInit;
    interface BlazeStrobe as Idle;
    interface BlazeStrobe as SRES;
    interface BlazeStrobe as SXOFF;
    interface BlazeStrobe as SFRX;
    interface BlazeStrobe as SFTX;
    interface BlazeStrobe as SRX;
    interface BlazeStrobe as SNOP;
    
    interface BlazeRegister as PaReg;
    
    interface Leds;
    
    //interface DebugPins as Pins;
  }
}

implementation {

  enum {
    NO_RADIO = 0xFF,
  };

  norace uint8_t m_id;
  
  uint8_t state[uniqueCount(UQ_BLAZE_RADIO)];
  
  enum {
    S_OFF,
    S_STARTING,
    S_ON,
    S_COMMITTING,
    S_STOPPING,
  };
  
  /***************** Prototypes ****************/

  /************** SoftwareInit Commands *****************/
  command error_t Init.init() {
    uint8_t i;
    for(i = 0; i < uniqueCount(UQ_BLAZE_RADIO); i++) {
      call BlazePower.shutdown[i]();
      state[i] = S_OFF;
    }
    m_id = NO_RADIO;
    return SUCCESS;
  }
    
  /************** SplitControl Commands**************/
  /**
   * This layer prevents two radios from being on simulatenously
   * When doing a SplitControl.start(), the radio is reset before bursting
   * in register values.  Tests show that not restarting the radio
   * somehow, even with different applications loaded on, will prevent
   * SplitControl.start from completing properly.  
   * 
   * It may have something to do with the corrupted register writes on burst.
   */
  command error_t SplitControl.start[ radio_id_t id ]() {
    
    if(id >= uniqueCount(UQ_BLAZE_RADIO)) {
      return EINVAL;
    }
    
    if(state[id] == S_ON) {
      return EALREADY;
      
    } else if(state[id] == S_STARTING) {
      return SUCCESS;
      
    } else if(state[id] != S_OFF) {
      return EBUSY;
    }
    
    // We must be in state S_OFF for this radio. 
    atomic m_id = id;
    
    call ReceiveSplitControl.start[m_id]();
    // Continues at ReceiveSplitControl.startDone...
    return SUCCESS;
  }
  
  command error_t SplitControl.stop[ radio_id_t id ]() {
    if(state[id] == S_OFF) {
      return EALREADY;
    
    } else if(state[id] == S_STOPPING) {
      return SUCCESS;
      
    } else if(state[id] != S_ON) {
      return EBUSY;
    }
    
    atomic m_id = id;
    
    call ReceiveSplitControl.stop[id]();
    return SUCCESS;
    // Continues at ReceiveSplitControl.stopDone()
  }
  
  
  /***************** ReceiveSplitControl Events ****************/
  event void ReceiveSplitControl.startDone[radio_id_t id](error_t error) {
    call Power.set[ m_id ]();

    state[ m_id ] = S_STARTING;
    
    call BlazePower.reset[ m_id ]();
  }
  
  event void ReceiveSplitControl.stopDone[radio_id_t id](error_t error) {
    call Gdo0_int.disable[ m_id ]();
    call Gdo2_int.disable[ m_id ]();
    
    call BlazePower.deepSleep[m_id]();
    call BlazePower.shutdown[m_id]();
    
    state[m_id] = S_OFF;
    signal SplitControl.stopDone[ m_id ](SUCCESS);
  }
  
  /***************** BlazeCommit Commands ****************/
  /** 
   * Commit register changes in RAM to hardware.
   * Note that this is not parameterized by radio to save footprint.  
   * The only radio we can commit changes to is the one that's currently 
   * turned on, indicated by m_id.
   *
   * It is up to higher layers to make sure we aren't trying to commit
   * registers to a different radio than the one currently turned on
   */
   
  
  command error_t BlazeCommit.commit[radio_id_t id]() {
    atomic m_id = id;
    
    if(state[m_id] != S_ON) {
      // Will be committed automatically next time the radio turns on..
      signal BlazeCommit.commitDone[id]();
      return SUCCESS;
    }
    
    state[m_id] = S_COMMITTING;    
    return call BlazePower.reset[m_id]();
  }
  
  
  /***************** BlazePower Commands ****************/

  /**
   * Restart the chip.  All registers come up in their default settings.
   * We don't confirm the radio ID or state, so be careful.  This is because
   * we may want to call BlazePower.reset() on some radio, and then call
   * SplitControl.start() afterwards.
   *
   * Note that the client calling this may be internal or external, and could
   * be different than the id we're servicing elsewhere.  So we keep the id
   * in a separate location (m_id)
   */
  async command error_t BlazePower.reset[ radio_id_t id ]() {
    atomic m_id = id;
    return call ResetResource.request();
  }
  
  /**
   * Stop the oscillator.
   * We don't confirm the radio ID, so be careful
   */
  async command error_t BlazePower.deepSleep[ radio_id_t id ]() {
    atomic m_id = id;
    return call DeepSleepResource.request();
  }

  /**
   * Completely power down radios on platforms that have a power pin
   */
  async command void BlazePower.shutdown[ radio_id_t id ]() {
    call Gdo0_io.makeOutput[ id ]();
    call Gdo2_io.makeOutput[ id ]();
    
    call Gdo0_io.clr[ id ]();
    call Gdo2_io.clr[ id ]();
    
    call Power.clr[ id ]();
  }
  
  async command bool BlazePower.isOn[ radio_id_t id ]() {
    return state[id] == S_ON;
  }
  
  /***************** RadioInit Events ****************/
  event void RadioInit.initDone() { 
    uint8_t cnt = 0;
    uint8_t iSwearItsGottaBeTheSilicon = 0;
    
    call Gdo0_io.makeInput[ m_id ]();
    call Gdo2_io.makeInput[ m_id ]();
    
    call Csn.set[ m_id ]();
    call Csn.clr[ m_id ]();
    
    // Startup the radio in Rx mode by default
    call Idle.strobe();
    call SFRX.strobe();
    call SFTX.strobe();
    
    call Gdo2_int.enableRisingEdge[ m_id ]();
    
    while(call RadioStatus.getRadioStatus() != BLAZE_S_IDLE) {
      ////call Leds.set(4);
      call Idle.strobe();
    } 
    
    call PaReg.write(call BlazeRegSettings.getPa[ m_id ]());
    
    call SRX.strobe();
    while(call RadioStatus.getRadioStatus() != BLAZE_S_RX) {
      /*
      ////call Leds.set(5);
      cnt++;
      
      if(cnt == 0xFF){    
        iSwearItsGottaBeTheSilicon++;
        
        // 2 is arbitrarily chosen here to give up.
        // This is an extremely rare and intermittent edge case only reproducible
        // a handful of times where the radio refuses to enter the correct state.
        if(iSwearItsGottaBeTheSilicon == 2) {
          call Csn.set[m_id]();
          call ResetResource.release();
          call BlazePower.shutdown[m_id]();
          call Power.set[ m_id ]();
          state[ m_id ] = S_STARTING;
          call BlazePower.reset[ m_id ]();
          return;
        }
          
        cnt = 0;
        call Csn.set[m_id]();
        call Csn.clr[m_id]();
        //call Pins.toggle65();
        call SFRX.strobe();
        call SFTX.strobe();
        call SRX.strobe();
        
      }*/
    }
        
    //call Pins.clr65();
    call Csn.set[ m_id ]();
    
    call ResetResource.release();
    
    if(state[m_id] == S_STARTING) {
      state[m_id] = S_ON;
      signal SplitControl.startDone[ m_id ](SUCCESS);
    
    } else {
      state[m_id] = S_ON;
      signal BlazeCommit.commitDone[ m_id ]();
    }
  }
  
  /***************** Resource Events ****************/
  event void ResetResource.granted() {
    uint8_t id;
    uint8_t cnt = 0;
    atomic id = m_id;
    
    call RadioReset.blockUntilPowered[id]();
    
    call Csn.clr[id]();
    
    while((call SNOP.strobe() & 0x80) != 0){
      /*
      cnt++;
      if(cnt == 0xFF) {
        call Csn.set[id]();
        call Csn.clr[id](); 
        cnt = 0;
      }
      */
    }
    
    call Csn.set[id]();
    
    if(state[id] == S_STARTING || state[id] == S_COMMITTING) {

      call Csn.clr[id]();
      call Idle.strobe();
    
      call RadioInit.init(BLAZE_IOCFG2, 
          call BlazeRegSettings.getDefaultRegisters[ id ](), 
              BLAZE_TOTAL_INIT_REGISTERS);
              
      // Hang onto the ResetResource until RadioInit has completed
              
    } else {
      call ResetResource.release();
      signal BlazePower.resetComplete[id]();
    }
  }
  
  event void DeepSleepResource.granted() {
    uint8_t id;
    atomic id = m_id;
    call Csn.set[id]();
    call Csn.clr[id]();
    call Idle.strobe();
    call SXOFF.strobe();
    call Csn.set[id]();
    call DeepSleepResource.release();
    signal BlazePower.deepSleepComplete[id]();
  }
  

  /***************** Interrupts ****************/
  async event void Gdo0_int.fired[radio_id_t id]() {
  }
  
  async event void Gdo2_int.fired[radio_id_t id]() {
  }
  
  /***************** Functions ****************/
    
  /***************** Tasks ****************/
  
  /***************** Defaults ******************/
  default async command void Csn.set[ radio_id_t id ](){}
  default async command void Csn.clr[ radio_id_t id ](){}
  default async command void Csn.toggle[ radio_id_t id ](){}
  default async command bool Csn.get[ radio_id_t id ](){return FALSE;}
  default async command void Csn.makeInput[ radio_id_t id ](){}
  default async command bool Csn.isInput[ radio_id_t id ](){return FALSE;}
  default async command void Csn.makeOutput[ radio_id_t id ](){}
  default async command bool Csn.isOutput[ radio_id_t id ](){return FALSE;}
  
  default async command void Power.set[ radio_id_t id ](){}
  default async command void Power.clr[ radio_id_t id ](){}
  default async command void Power.toggle[ radio_id_t id ](){}
  default async command bool Power.get[ radio_id_t id ](){return FALSE;}
  default async command void Power.makeInput[ radio_id_t id ](){}
  default async command bool Power.isInput[ radio_id_t id ](){return FALSE;}
  default async command void Power.makeOutput[ radio_id_t id ](){}
  default async command bool Power.isOutput[ radio_id_t id ](){return FALSE;}

  default async command void Gdo0_io.set[ radio_id_t id ](){}
  default async command void Gdo0_io.clr[ radio_id_t id ](){}
  default async command void Gdo0_io.toggle[ radio_id_t id ](){}
  default async command bool Gdo0_io.get[ radio_id_t id ](){return FALSE;}
  default async command void Gdo0_io.makeInput[ radio_id_t id ](){}
  default async command bool Gdo0_io.isInput[ radio_id_t id ](){return FALSE;}
  default async command void Gdo0_io.makeOutput[ radio_id_t id ](){}
  default async command bool Gdo0_io.isOutput[ radio_id_t id ](){return FALSE;}
  
  default async command void Gdo2_io.set[ radio_id_t id ](){}
  default async command void Gdo2_io.clr[ radio_id_t id ](){}
  default async command void Gdo2_io.toggle[ radio_id_t id ](){}
  default async command bool Gdo2_io.get[ radio_id_t id ](){return FALSE;}
  default async command void Gdo2_io.makeInput[ radio_id_t id ](){}
  default async command bool Gdo2_io.isInput[ radio_id_t id ](){return FALSE;}
  default async command void Gdo2_io.makeOutput[ radio_id_t id ](){}
  default async command bool Gdo2_io.isOutput[ radio_id_t id ](){return FALSE;}
  
  default async command error_t Gdo0_int.enableRisingEdge[radio_id_t id]() { return FAIL; }
  default async command error_t Gdo0_int.enableFallingEdge[radio_id_t id]() { return FAIL; }
  default async command error_t Gdo0_int.disable[radio_id_t id]() { return FAIL; }
  
  default async command error_t Gdo2_int.enableRisingEdge[radio_id_t id]() { return FAIL; }
  default async command error_t Gdo2_int.enableFallingEdge[radio_id_t id]() { return FAIL; }
  default async command error_t Gdo2_int.disable[radio_id_t id]() { return FAIL; }
  
  default event void BlazePower.resetComplete[ radio_id_t id ]() {}
  default event void BlazePower.deepSleepComplete[ radio_id_t id ]() {}
  
  default event void SplitControl.startDone[ radio_id_t id ](error_t error){}
  default event void SplitControl.stopDone[ radio_id_t id ](error_t error){}
  
  default command blaze_init_t *BlazeRegSettings.getDefaultRegisters[ radio_id_t id ]() { return NULL; }
  default command uint8_t BlazeRegSettings.getPa[ radio_id_t id ]() { return 0xC0; }
  
  default event void BlazeCommit.commitDone[ radio_id_t id ]() {}
}