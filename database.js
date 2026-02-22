import "dotenv/config"
import pgPromise from 'pg-promise';
const pgp = pgPromise();
export const db = pgp({
  user: 'postgres',
  password: process.env.PG_PASSWORD,
  host: 'postgresql',
  port: 5432,
  database: 'leantify',
});

