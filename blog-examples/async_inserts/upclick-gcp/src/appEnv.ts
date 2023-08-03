import dotenv from 'dotenv';
import joi from 'joi';
import path from 'path';

interface Config {
  appName: String;
  clickhouseHost: string;
}

interface Secret {
  clickhouseUsername: string;
  clickhousePassword: string;
  maxMindAccountId: string;
  maxMindLicenseKey: string;
}

export interface AppEnv {
  config: Config;
  secret: Secret;
}

// VALIDATION
// schema depicting what to expect in the env key=val file
const SECRETS_ENV_VAR_JOI_SCHEMA = joi
  .object()
  .keys({
    // app
    APP_NAME: joi.string().required(),
    // clickhouse
    CLICKHOUSE_HOST: joi
      .string()
      .regex(/^[http(s)?://[^$]+/)
      .required(),
    CLICKHOUSE_USERNAME: joi.string().required(),
    CLICKHOUSE_PASSWORD: joi.string().required(),
    // maxmind
    MAXMIND_LICENSE_KEY: joi.string().required(),
    MAX_MIND_ACCOUNT_ID: joi.string().required(),
  })
  .unknown();

export const loadEnv = () => {
  // path to secrets
  const appEnvFilePath = path.join(__dirname, '.env');

  // load file
  console.log(`Loading env from ${path.join(__dirname, '../.env')}`);

  // load with .env
  dotenv.config({ path: appEnvFilePath });

  // validate with joi
  const { value: envVars, error } = SECRETS_ENV_VAR_JOI_SCHEMA.prefs({
    errors: { label: 'key' },
  }).validate(process.env);

  if (error) {
    throw new Error(`Config validation error: ${error.message}`);
  } else {
    console.log('loaded secrets...');
    const appEnv: AppEnv = {
      config: {
        appName: envVars.APP_NAME,
        clickhouseHost: envVars.CLICKHOUSE_HOST,
      },
      secret: {
        clickhousePassword: envVars.CLICKHOUSE_PASSWORD,
        clickhouseUsername: envVars.CLICKHOUSE_USERNAME,
        maxMindAccountId: envVars.MAX_MIND_ACCOUNT_ID,
        maxMindLicenseKey: envVars.MAXMIND_LICENSE_KEY,
      },
    };
    return appEnv;
  }
};

export const APPENV = loadEnv();
