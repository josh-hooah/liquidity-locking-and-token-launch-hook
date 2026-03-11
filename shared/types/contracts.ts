export type Address = `0x${string}`;

export interface DeploymentAddresses {
  poolManager: Address;
  vault: Address;
  launchManager: Address;
  hook: Address;
  hookDeployer: Address;
  launchToken?: Address;
  pairedToken?: Address;
}

export interface LaunchProgress {
  unlockedBps: number;
  withdrawable0: string;
  withdrawable1: string;
  cumulativeVolumeToken0: string;
  cumulativeVolumeToken1: string;
}
