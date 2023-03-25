const hre = require("hardhat");

let escrow;
let stakePool;
let lpPool;
const CTZN = "0xa803778ab953d3ffe4fbd20cfa0042ecefe8319d";
const LP = "0x3e436C4908c64c93d80Ca6A2694B53bD970C4e33";
const owner = "0x6934b7875fEABE4FA129D4988ca6DEcD1Dca9C2B";

async function CTZNPool() {
  try {
    console.log("Staking contract starts:");
    var contract = await ethers.getContractFactory(
      "TimeLockNonTransferablePool"
    );
    stakePool = await contract.deploy("Staked CTZN", "SCTZN", CTZN, CTZN);

    console.log("stakePool deployed to:", stakePool.address);

    console.log("Assigning REWARD_DISTRIBUTOR_ROLE for CTZN Stake Pool");
    const CTZN_REWARD_DISTRIBUTOR_ROLE =
      await stakePool.REWARD_DISTRIBUTOR_ROLE();
    console.log("before CRD");
    await stakePool.grantRole(CTZN_REWARD_DISTRIBUTOR_ROLE, owner);
    console.log("after CRD");
  } catch (error) {
    console.log("error at 2:", error);
  }
}

async function CTZNLPPool() {
  try {
    var contract = await ethers.getContractFactory(
      "TimeLockNonTransferablePool"
    );

    lpPool = await contract.deploy("CTZN/BUSD CAKE-LP", "SCTZNLP", LP, CTZN);

    console.log("lpPool deployed to:", lpPool.address);

    console.log("Assigning REWARD_DISTRIBUTOR_ROLE for CTZN LP Pool");
    const LP_REWARD_DISTRIBUTOR_ROLE = await lpPool.REWARD_DISTRIBUTOR_ROLE();
    await lpPool.grantRole(LP_REWARD_DISTRIBUTOR_ROLE, owner);
  } catch (error) {
    console.log("error at 2:", error);
  }
}

async function View() {
  try {
    var contract = await ethers.getContractFactory("View");

    const view = await contract.deploy([stakePool.address, lpPool.address]);

    // await view.deployed();
    console.log("view deployed to:", view.address);
  } catch (error) {}
}

async function main() {
  try {
    await CTZNPool();
    await CTZNLPPool();
    await View();
  } catch (error) {
    console.log("main: ", error);
  }
}

main();
