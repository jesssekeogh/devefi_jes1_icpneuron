import { PocketIc, SubnetStateType } from "@hadronous/pic";
import { Principal } from "@dfinity/principal";
import { NNS_STATE_PATH, NNS_SUBNET_ID } from "./constants.ts";

export class Setup {
  private readonly pic: PocketIc;

  constructor(pic: PocketIc) {
    this.pic = pic;
  }

  public static async beforeAll(): Promise<Setup> {
    // setup pocket IC
    let pic = await PocketIc.create(process.env.PIC_URL, {
      nns: {
        state: {
          type: SubnetStateType.FromPath,
          path: NNS_STATE_PATH,
          subnetId: Principal.fromText(NNS_SUBNET_ID),
        },
      },
    });

    await pic.setTime(new Date().getTime());
    await pic.tick();

    return new Setup(pic);
  }

  public async afterAll(): Promise<void> {
    await this.pic.tearDown();
  }

  public getPicInstance(): PocketIc {
    return this.pic;
  }
}
