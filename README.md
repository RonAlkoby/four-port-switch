# Four-Port Packet Switch

This project implements a four-port packet switch using SystemVerilog.
The switch receives packets on any input port and routes them to one or more output ports
according to a one-hot encoded target field.

## Features
- Modular RTL design (RX, TX, FIFO, arbitration)
- Support for single-destination, multicast, and broadcast packets
- Correct handling of contention between multiple input ports
- SystemVerilog testbench with multiple directed tests
- Verified using waveform-based analysis

## Packet Format
- Source: 4-bit one-hot encoded input port
- Target: 4-bit one-hot encoded destination port(s)
- Data: 8-bit payload

## Test Scenarios
- Single destination routing
- Multicast routing
- Broadcast routing
- Heavy contention (multiple sources to same destination)
- Sequential packets from the same source

## Directory Structure
- `rtl/` – RTL implementation
- `tb/` – Testbench and interfaces
- `sim/` – Simulation scripts
- `doc/` – Documentation and reports

## Tools
- SystemVerilog
- Synopsys Euclide

