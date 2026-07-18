import { prisma } from '../dist/config/prisma.js';
import { env } from '../dist/config/env.js';
import jwt from 'jsonwebtoken';
import fs from 'fs';
import path from 'path';

async function test() {
  const partner = await prisma.partner.findFirst();
  if (!partner) {
    console.error("No partner found");
    return;
  }
  
  const token = jwt.sign({
    sub: partner.partner_id,
    role: 'partner',
    status: 'active'
  }, env.JWT_ACCESS_SECRET, { expiresIn: '15m' });
  
  // Create a mock file
  const tempFile = path.join(process.cwd(), 'scratch/temp_test.png');
  fs.writeFileSync(tempFile, 'dummy content');
  
  const formData = new FormData();
  const fileBlob = new Blob([fs.readFileSync(tempFile)], { type: 'image/png' });
  formData.append('file', fileBlob, 'temp_test.png');
  
  try {
    const res = await fetch('http://localhost:4000/api/upload', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`
      },
      body: formData
    });
    const json = await res.json();
    console.log("Response:", json);
  } catch (err) {
    console.error("Error:", err.message);
  } finally {
    if (fs.existsSync(tempFile)) {
      fs.unlinkSync(tempFile);
    }
  }
}

test();
