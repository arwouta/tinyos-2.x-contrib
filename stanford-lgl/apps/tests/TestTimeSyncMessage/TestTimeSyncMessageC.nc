/*
* Copyright (c) 2006 Stanford University.
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
* - Neither the name of the Stanford University nor the names of
*   its contributors may be used to endorse or promote products derived
*   from this software without specific prior written permission
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
* ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
* LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
* FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL STANFORD
* UNIVERSITY OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
* INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
* SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
* HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
* STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
* OF THE POSSIBILITY OF SUCH DAMAGE.
*/
/**
 * @author Brano Kusy (branislav.kusy@gmail.com)
 */

#include "TestTimeSyncMessage.h"

configuration TestTimeSyncMessageC
{
}

implementation
{
    components TestTimeSyncMessageM,  MainC, LedsC;

    TestTimeSyncMessageM -> MainC.Boot;
    TestTimeSyncMessageM.Leds -> LedsC;

    components ActiveMessageC;
    TestTimeSyncMessageM.RadioControl   -> ActiveMessageC;
    TestTimeSyncMessageM.ReportSend     -> ActiveMessageC.AMSend[AM_TIMESYNCPOLLREPORT];
    
    components TimeSyncMessageC as TSActiveMessageC, CC2420PacketC;
    TestTimeSyncMessageM.PollSend     -> TSActiveMessageC.TimeSyncAMSendMilli[AM_TIMESYNCPOLL];
    TestTimeSyncMessageM.PollReceive  -> TSActiveMessageC.Receive[AM_TIMESYNCPOLL];
    TestTimeSyncMessageM.PollPacket   -> TSActiveMessageC;
    TestTimeSyncMessageM.TimeSyncPacket -> TSActiveMessageC;
    TestTimeSyncMessageM.PacketTimeStamp -> CC2420PacketC;

    components HilTimerMilliC;
    TestTimeSyncMessageM.LocalTime       ->  HilTimerMilliC;

    components new TimerMilliC() as Timer1;
    TestTimeSyncMessageM.Timer1     -> Timer1;
    components new TimerMilliC() as Timer2;
    TestTimeSyncMessageM.Timer2     -> Timer2;
}
