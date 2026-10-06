Vendored from https://github.com/SideStore/minimuxer at 12be70dc2627307a16bfd2dc7a009080d5bec909 (AGPL-3.0, see Vendor/minimuxer/LICENSE). One modification (below).
Modification: DeviceGateway/Package.swift pins RemotePairingKit to revision e3f70d16c0c551540a533a39d540e78e5b0a60a8 instead of branch main.
Modification: DeviceGateway/Package.swift IDevice binaryTarget now points at ../../IDevice.xcframework, built in CI from SideStore/idevice 3e55c8486b2057e40c1f74aaaa1155c82341cf76 with extra feature location_simulation.
Modification: Common/MinimuxerConstants.swift DDI URLs pinned to doronz88/DeveloperDiskImage commit 9fa2d08e75084c0ea0f27575e2e4b47399056933 (DDI 17E5179g) instead of refs/heads/main.
Modification: added setSimulatedLocation/clearSimulatedLocation (calls location_simulation_new/set/clear from the locally built idevice FFI) in DeviceGateway/idevice/IdeviceGateway.swift, DeviceGateway/DeviceGatewayAPI.swift, Sources/MinimuxerApi.swift, Sources/MinimuxerImpl.swift.
