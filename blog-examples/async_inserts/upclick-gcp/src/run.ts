import axios from 'axios';
import { City, WebServiceClient } from '@maxmind/geoip2-node';
import { APPENV } from './appEnv';
import { DateTime } from 'luxon';

const DATABASE = 'default';
const TABLE = 'upclick_metrics';

interface WebMetric {
  target: string;
  status_code: number;
  latency: number;
  continent_code?: string;
  country_iso_code?: string;
  country_name_en?: string;
  city_name_en?: string;
  latitude?: number;
  longitude?: number;
}

export const run = async (target: string) => {
  // get my IP
  const ipifyResponse = await axiosGet('https://api.ipify.org');

  // use IP to get my geo data
  const geoDataResponse: City = await getGeoData(ipifyResponse.data);

  // measure time
  const startTime = DateTime.now();

  // send a GET to the target site
  const targetSiteRepsonse = await axiosGet(`http://${target}`);

  // build metrics based on both geo and HTTP response values
  const metric: WebMetric = prepMetric(
    geoDataResponse,
    target,
    targetSiteRepsonse.status,
    startTime,
  );

  console.log(`Sending metrics to ClickHouse...\n${JSON.stringify(metric)}`);

  // build the INSERT
  const query = `INSERT INTO ${DATABASE}.${TABLE} VALUES ('${metric.target}',${metric.status_code},${metric.latency},'${metric.continent_code}','${metric.country_iso_code}','${metric.country_name_en}','${metric.city_name_en}',${metric.latitude},${metric.longitude})`;

  const clickhouseResponse = await axiosPostClickhouseInsert(
    APPENV.config.clickhouseHost,
    query,
    'default',
    APPENV.secret.clickhouseUsername,
    APPENV.secret.clickhousePassword,
  );

  console.log(`done...bye!`);
};

const axiosGet = async (url: string) => {
  const response = await axios.get(url);
  if (response.status === 200) {
    // return the public detected public IP
    return response;
  }
  throw new Error(
    `Get request failed!\nstatus code:[${response.status}] url:[:${url}]`,
  );
};

const axiosPostClickhouseInsert = async (
  url: string,
  query: string,
  database: string,
  username: string,
  password: string,
) => {
  const response = await axios.post(url, undefined, {
    params: { query, database },
    headers: {
      'X-ClickHouse-User': username,
      'X-ClickHouse-Key': password,
    },
  });
  return response;
};

const getGeoData = async (ip: string) => {
  const client = new WebServiceClient(
    APPENV.secret.maxMindAccountId,
    APPENV.secret.maxMindLicenseKey,
    { host: 'geolite.info' },
  );
  const geoDataCity = await client.city(ip);
  return geoDataCity;
};

const prepMetric = (
  getGeoData: City,
  target: string,
  statusCode: number,
  startTime: DateTime,
): WebMetric => {
  return {
    target,
    status_code: statusCode,
    latency: DateTime.now().diff(startTime).toMillis(),
    continent_code: getGeoData.continent?.code,
    country_iso_code: getGeoData.country?.isoCode,
    country_name_en: getGeoData.country?.names.en,
    city_name_en: getGeoData.city?.names.en,
    latitude: getGeoData.location?.latitude,
    longitude: getGeoData.location?.longitude,
  };
};
