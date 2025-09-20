# DynEscrow - Dynamic Escrow for IoT Shipment Tracking

## Overview

DynEscrow is a blockchain-based smart contract system that provides dynamic escrow services tied to IoT shipment tracking. This system enables secure, automated transactions that release funds based on real-world shipment milestones verified through IoT sensors and devices.

## Features

- **IoT Integration**: Direct integration with shipment tracking devices and sensors
- **Dynamic Release Conditions**: Funds are released based on shipment status and conditions
- **Multi-Party Security**: Secure escrow between buyers, sellers, and logistics providers
- **Automated Execution**: Smart contracts automatically execute based on IoT data
- **Transparency**: All parties can track shipment progress and escrow status
- **Dispute Resolution**: Built-in mechanisms for handling shipment issues

## System Architecture

### Core Components

1. **Escrow Manager Contract**: Main contract handling escrow creation, management, and fund releases
2. **IoT Tracker Contract**: Handles IoT device data verification and shipment milestone tracking

### Key Features

- **Escrow Creation**: Create escrows with specific IoT tracking requirements
- **Milestone Tracking**: Track key shipment milestones (pickup, transit, delivery)
- **Conditional Releases**: Automatic fund release based on IoT-verified conditions
- **Emergency Controls**: Safety mechanisms for dispute resolution
- **Multi-signature Support**: Enhanced security through multi-party validation

## Smart Contract Details

### Escrow Manager
- Manages escrow lifecycle from creation to completion
- Handles fund deposits, holds, and releases
- Integrates with IoT data for automated decision making
- Provides dispute resolution mechanisms

### IoT Tracker
- Validates IoT device authenticity and data integrity
- Tracks shipment locations, temperatures, and other sensor data
- Provides milestone verification for escrow releases
- Maintains audit trail of all IoT interactions

## Use Cases

1. **Temperature-Sensitive Goods**: Pharmaceuticals, food products
2. **High-Value Electronics**: Ensuring proper handling and delivery
3. **International Shipping**: Cross-border transactions with multiple checkpoints
4. **Supply Chain Finance**: Working capital solutions tied to shipment progress

## Getting Started

### Prerequisites

- Clarinet CLI installed
- Node.js and npm for testing
- Access to IoT tracking devices (for production use)

### Installation

```bash
git clone <repository-url>
cd DynEscrow
npm install
```

### Testing

```bash
clarinet check
npm test
```

## Contract Deployment

The contracts are designed for deployment on the Stacks blockchain and can be deployed to:
- Local development environment
- Testnet for testing
- Mainnet for production use

## Security Considerations

- All IoT data is validated before being used in escrow decisions
- Multi-signature requirements for high-value transactions
- Time-based failsafes to prevent indefinite fund locks
- Regular security audits and updates

## Contributing

Please read our contributing guidelines before submitting pull requests.

## License

This project is licensed under the MIT License.
