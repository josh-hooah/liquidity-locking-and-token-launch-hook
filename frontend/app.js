const { ethers } = window;

const launchManagerAbi = await (await fetch("../shared/abi/LaunchManager.json")).json();
const vaultAbi = await (await fetch("../shared/abi/LiquidityLockVault.json")).json();
const erc20Abi = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function decimals() view returns (uint8)"
];

const poolManagerAbi = ["function initialize((address,address,uint24,int24,address) key, uint160 sqrtPriceX96) external returns (int24)"];
const modifyLiquidityAbi = [
  "function modifyLiquidity((address,address,uint24,int24,address) key, (int24 tickLower, int24 tickUpper, int128 liquidityDelta, bytes32 salt) params, bytes hookData) external returns (int256)"
];
const swapRouterAbi = [
  "function swap((address,address,uint24,int24,address) key, (bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96) params, (bool takeClaims, bool settleUsingBurn) testSettings, bytes hookData) external returns (int256)"
];

let provider;
let signer;

const byId = (id) => document.getElementById(id);
const out = (id, msg) => {
  byId(id).textContent = msg;
};

function asBool(v) {
  return String(v).trim().toLowerCase() === "true";
}

function asBig(v) {
  return BigInt(String(v || "0").trim());
}

function parseCsvBig(v) {
  const clean = String(v || "").trim();
  if (!clean) return [];
  return clean.split(",").map((x) => BigInt(x.trim()));
}

function parseCsvNum(v) {
  const clean = String(v || "").trim();
  if (!clean) return [];
  return clean.split(",").map((x) => Number(x.trim()));
}

function buildKey() {
  return {
    currency0: byId("token0").value.trim(),
    currency1: byId("token1").value.trim(),
    fee: Number(byId("fee").value),
    tickSpacing: Number(byId("tickSpacing").value),
    hooks: byId("hookAddress").value.trim()
  };
}

function manager() {
  return new ethers.Contract(byId("launchManagerAddress").value.trim(), launchManagerAbi, signer);
}

function vault() {
  return new ethers.Contract(byId("vaultAddress").value.trim(), vaultAbi, signer);
}

byId("connectBtn").onclick = async () => {
  if (!window.ethereum) {
    byId("walletStatus").textContent = "No injected wallet detected";
    return;
  }

  provider = new ethers.BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  byId("walletStatus").textContent = `Connected: ${await signer.getAddress()}`;
};

byId("createLaunchBtn").onclick = async () => {
  try {
    const m = manager();

    const cfg = {
      launchStartTime: Number(byId("launchStart").value),
      launchEndTime: Number(byId("launchEnd").value),
      pairedAsset: byId("pairedAsset").value.trim(),
      referenceTick: Number(byId("referenceTick").value)
    };

    const policy = {
      mode: Number(byId("mode").value),
      timeCliffSeconds: Number(byId("timeCliff").value),
      timeEpochSeconds: Number(byId("timeEpoch").value),
      timeUnlockBpsPerEpoch: Number(byId("timeUnlockBps").value),
      minTradeSizeForVolume: asBig(byId("minTradeSize").value),
      maxTxAmountInLaunchWindow: asBig(byId("maxTx").value),
      cooldownSecondsPerAddress: Number(byId("cooldown").value),
      stabilityBandTicks: Number(byId("stabilityBand").value),
      stabilityMinDurationSeconds: Number(byId("stabilityDuration").value),
      emergencyPause: asBool(byId("emergencyPause").value),
      volumeMilestones: parseCsvBig(byId("milestones").value),
      unlockBpsAtMilestone: parseCsvNum(byId("milestoneBps").value)
    };

    const tx = await m.createLaunch(buildKey(), cfg, policy);
    out("createLaunchOut", `Submitted: ${tx.hash}`);
    await tx.wait();

    const poolId = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(address,address,uint24,int24,address)"],
        [Object.values(buildKey())]
      )
    );
    byId("poolId").value = poolId;

    out("createLaunchOut", `Launch created. Tx: ${tx.hash}\nPoolId: ${poolId}`);
  } catch (err) {
    out("createLaunchOut", `Create launch failed: ${err}`);
  }
};

byId("initializePoolBtn").onclick = async () => {
  try {
    const contract = new ethers.Contract(byId("poolManagerAddress").value.trim(), poolManagerAbi, signer);
    const tx = await contract.initialize(buildKey(), asBig(byId("sqrtPrice").value));
    out("seedOut", `Pool initialize tx: ${tx.hash}`);
    await tx.wait();
  } catch (err) {
    out("seedOut", `Pool initialize failed: ${err}`);
  }
};

byId("seedLiquidityBtn").onclick = async () => {
  try {
    const router = new ethers.Contract(byId("modifyRouterAddress").value.trim(), modifyLiquidityAbi, signer);
    const params = {
      tickLower: Number(byId("tickLower").value),
      tickUpper: Number(byId("tickUpper").value),
      liquidityDelta: BigInt(byId("liquidityDelta").value),
      salt: byId("positionSalt").value.trim()
    };
    const tx = await router.modifyLiquidity(buildKey(), params, "0x");
    out("seedOut", `Liquidity seed tx: ${tx.hash}`);
    await tx.wait();
  } catch (err) {
    out("seedOut", `Liquidity seed failed: ${err}`);
  }
};

byId("depositLockBtn").onclick = async () => {
  try {
    const v = byId("vaultAddress").value.trim();
    const t0 = new ethers.Contract(byId("token0").value.trim(), erc20Abi, signer);
    const t1 = new ethers.Contract(byId("token1").value.trim(), erc20Abi, signer);

    const a0 = asBig(byId("lockAmount0").value);
    const a1 = asBig(byId("lockAmount1").value);

    await (await t0.approve(v, a0)).wait();
    await (await t1.approve(v, a1)).wait();

    const tx = await manager().depositLockedLiquidity(byId("poolId").value.trim(), a0, a1);
    out("seedOut", `Lock deposit tx: ${tx.hash}`);
    await tx.wait();
  } catch (err) {
    out("seedOut", `Lock deposit failed: ${err}`);
  }
};

byId("runSwapsBtn").onclick = async () => {
  try {
    const router = new ethers.Contract(byId("swapRouterAddress").value.trim(), swapRouterAbi, signer);
    const amounts = parseCsvBig(byId("swapAmounts").value);
    const zeroForOne = asBool(byId("zeroForOne").value);
    const limit = asBig(byId("sqrtPriceLimit").value);

    const logs = [];
    for (const amount of amounts) {
      try {
        const tx = await router.swap(
          buildKey(),
          { zeroForOne, amountSpecified: -amount, sqrtPriceLimitX96: limit },
          { takeClaims: false, settleUsingBurn: false },
          "0x"
        );
        logs.push(`ok ${amount}: ${tx.hash}`);
        await tx.wait();
      } catch (err) {
        logs.push(`blocked ${amount}: ${err}`);
      }
    }

    out("progressOut", logs.join("\n"));
  } catch (err) {
    out("progressOut", `Swap sequence failed: ${err}`);
  }
};

byId("advanceBtn").onclick = async () => {
  try {
    const tx = await manager().advance(byId("poolId").value.trim());
    out("progressOut", `Advance tx: ${tx.hash}`);
    await tx.wait();
  } catch (err) {
    out("progressOut", `Advance failed: ${err}`);
  }
};

byId("withdrawBtn").onclick = async () => {
  try {
    const a0 = asBig(byId("withdraw0").value);
    const a1 = asBig(byId("withdraw1").value);
    const to = await signer.getAddress();

    const tx = await manager().withdrawUnlockedLiquidity(byId("poolId").value.trim(), to, a0, a1);
    out("progressOut", `Withdraw tx: ${tx.hash}`);
    await tx.wait();
  } catch (err) {
    out("progressOut", `Withdraw failed: ${err}`);
  }
};

byId("refreshBtn").onclick = async () => {
  try {
    const poolId = byId("poolId").value.trim();
    const [state, preview, withdrawable] = await Promise.all([
      manager().getLaunchState(poolId),
      manager().previewAdvance(poolId),
      vault().withdrawableAmounts(poolId)
    ]);

    out(
      "progressOut",
      [
        `Current unlocked bps: ${state.unlockedBps}`,
        `Candidate unlocked bps: ${preview[1]}`,
        `Stability gate ok: ${preview[2]}`,
        `Volume0: ${state.cumulativeVolumeToken0}`,
        `Volume1: ${state.cumulativeVolumeToken1}`,
        `Withdrawable token0: ${withdrawable[0]}`,
        `Withdrawable token1: ${withdrawable[1]}`
      ].join("\n")
    );
  } catch (err) {
    out("progressOut", `Refresh failed: ${err}`);
  }
};

const now = Math.floor(Date.now() / 1000);
byId("launchStart").value = String(now + 30);
byId("launchEnd").value = String(now + 86400);
