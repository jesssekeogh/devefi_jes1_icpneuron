import { Setup } from "../setup/setup.ts";

describe("Test suite", () => {
  let setup: Setup;

  beforeAll(async () => {
    setup = await Setup.beforeAll();
  });

  afterAll(async () => {
    await setup.afterAll();
  });

  it("should do something cool", async () => {
    let vec = setup.getVector();
    let res = await vec.icrc55_get_pylon_meta();
    console.log(res);
    let icp = setup.getIcpLedger();
    let res2 = await icp.icrc1_metadata();
    console.log(res2);
    let icrc = setup.getIcrcLedger();
    let res3 = await icrc.icrc1_metadata();
    console.log(res3);
    expect("cool").toEqual("cool");
  });
});
