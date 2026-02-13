// db.js
const { Pool } = require("pg");

// Pool = connection pool (recommended in real apps)
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

module.exports = { pool };
