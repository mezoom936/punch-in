// db.js
// const { Pool } = require("pg");

// Pool = connection pool (recommended in real apps)
// const pool = new Pool({
//   connectionString: process.env.DATABASE_URL,
// });

// module.exports = { pool };

const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,

  // Railway + Render + cloud Postgres need SSL
  ssl: process.env.DATABASE_URL
    ? { rejectUnauthorized: false }
    : false,
});

module.exports = { pool };

