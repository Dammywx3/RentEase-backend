import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL is missing in .env");

const pool = new Pool({ connectionString: url });
const adapter = new PrismaPg(pool);

export const prisma = new PrismaClient({ adapter });