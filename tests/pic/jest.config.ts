import type { Config } from "jest";

const config: Config = {
  watch: false,
  verbose: true,
  preset: "ts-jest/presets/js-with-ts",
  testEnvironment: "node",
  globalSetup: "<rootDir>/global-setup.ts",
  globalTeardown: "<rootDir>/global-teardown.ts",
  testTimeout: 300_000,
  // maxWorkers: 1,
};

export default config;
