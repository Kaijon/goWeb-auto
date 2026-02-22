# Embedded Camera: Resolution and Bitrate Policy

## 1. Hardware Constraints
The camera hardware only supports the following configurations. The backend/host simulator will reject anything outside these ranges with error code `0x01 INVALID_PARAM`.

* **4K (3840x2160):** Allowed Bitrate = 8Mbps to 16Mbps.
* **2K (2560x1440):** Allowed Bitrate = 6Mbps to 12Mbps.
* **1080P (1920x1080):** Allowed Bitrate = < 6Mbps.

## 2. Web UI Requirements
Any web interface configuring these settings must implement the following:
* **Inputs:** Provide two dropdown selectors: one for "Resolution" and one for "Bitrate".
* **Dynamic Validation:** Implement reactive logic so that the "Bitrate" dropdown dynamically updates its available options based on the selected "Resolution". Use the Hardware Constraints above as the reference.