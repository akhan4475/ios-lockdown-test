Vendored from https://github.com/SideStore/minimuxer at 12be70dc2627307a16bfd2dc7a009080d5bec909 (AGPL-3.0, see Vendor/minimuxer/LICENSE). One modification (below).
Modification: DeviceGateway/Package.swift pins RemotePairingKit to revision e3f70d16c0c551540a533a39d540e78e5b0a60a8 instead of branch main.
Modification: DeviceGateway/Package.swift IDevice binaryTarget now points at ../../IDevice.xcframework, built in CI from SideStore/idevice 3e55c8486b2057e40c1f74aaaa1155c82341cf76 with extra feature location_simulation.
