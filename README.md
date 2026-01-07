# FPGA Pong Game with Web Bluetooth Control 🏓

**An embedded system project integrating an FPGA game engine with a wireless controller based on ESP32 and Web Bluetooth API.**

## 📖 Overview

This project demonstrates a full-stack embedded implementation of the classic Pong game. Unlike traditional implementations, this system decouples the game logic from the controller:
1.  **Game Logic & Video:** Runs entirely on hardware (FPGA) using VHDL.
2.  **Wireless Bridge:** An ESP32 microcontroller acts as a BLE Server to receive commands.
3.  **User Interface:** A Web Application runs on any smartphone/PC browser to control the paddles via Bluetooth Low Energy (BLE).

[cite_start]The goal was to prove the viability of low-latency wireless control for hardware-accelerated logic using modern web technologies[cite: 373, 515].

---

## 🏗️ System Architecture

The system is divided into three distinct layers, each represented by a file in this repository:

### 1. The Game Engine (Hardware Layer)
* **File:** `pong.vhdl`
* **Platform:** Intel MAX 10 FPGA (DE10-Lite Board).
* **Description:** This VHDL module implements the complete game physics, collision detection, score counting, and the **VGA Video Signal Generation** (800x600 resolution).
* [cite_start]**Input:** It reads digital logic levels from the GPIO pins to move the paddles up or down[cite: 384, 460].

### 2. The Wireless Bridge (Firmware Layer)
* **File:** `controle.c`
* **Platform:** ESP32 (ESP-IDF Framework).
* **Description:** The ESP32 acts as a **BLE Peripheral (GATT Server)**. It exposes a custom service to receive data from the web browser.
* [cite_start]**Logic:** When a command is received via Bluetooth (e.g., "Move Up"), the firmware toggles specific GPIO pins (GPIO 4 and 5) which are physically connected to the FPGA inputs[cite: 389, 420].

### 3. The Controller (Client Layer)
* **File:** `aplicaçãoWeb.html`
* **Platform:** Web Browser (Chrome/Edge).
* **Description:** A responsive HTML5/JS interface that uses the **Web Bluetooth API**. It connects directly to the ESP32 without needing a native app.
* [cite_start]**Logic:** It captures touch/mouse events and sends raw bytes to the ESP32 using "Write Without Response" to minimize latency[cite: 407, 416].

---

## 🔌 Hardware Connections

[cite_start]To replicate this project, the ESP32 GPIOs must be connected to the FPGA GPIOs (Arduino Header on DE10-Lite) via **330Ω protection resistors**[cite: 397].

| ESP32 Pin | FPGA Pin (Arduino IO) | Function |
| :--- | :--- | :--- |
| **GPIO 5** | IO Pin 2 / 3 | Player 1 Control (Up/Down) |
| **GPIO 4** | IO Pin 6 / 7 | Player 2 Control (Up/Down) |
| **GND** | GND | Common Ground |

*Note: The Logic on the FPGA is Active-Low.*

---

## 🚀 How to Run

1.  **FPGA:** Synthesize `pong.vhdl` using Quartus Prime and flash the DE10-Lite board. Connect the VGA output to a monitor.
2.  **ESP32:** Flash `controle.c` using the ESP-IDF framework to your ESP32 board.
3.  **Hardware:** Connect the ESP32 pins to the FPGA headers as described above. Power both boards.
4.  **Web:** Open `aplicaçãoWeb.html` in a BLE-supported browser (Chrome or Edge) on your PC or Android phone.
5.  **Play:** Click "Connect", select the ESP32 device, and use the on-screen buttons to control the paddles.

---

## 🛠️ Technologies Used
* **VHDL** (Intel Quartus Prime Lite)
* **C / ESP-IDF** (FreeRTOS based)
* **JavaScript / Web Bluetooth API**
* **HTML5 / CSS3** (Tailwind CSS)

## 👥 Authors
* **Victor Hugo Carvalho**
* Bruno Vinicius Machado Castanho
* Jamerson Muniz

**Institution:** Federal University of Technology – Paraná (UTFPR)

---

*Note: This repository contains the source files for the three main components. Circuit diagrams and full project binaries are not included.*
