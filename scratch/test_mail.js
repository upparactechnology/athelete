import nodemailer from 'nodemailer';

async function test() {
  try {
    const transporter = nodemailer.createTransport({
      host: 'smtp.gmail.com',
      port: 587,
      secure: false, // false for 587
      auth: {
        user: 'hetshah6312@gmail.com',
        pass: 'glep exwm zkcy muyp'
      }
    });

    console.log("Sending test email...");
    const info = await transporter.sendMail({
      from: 'hetshah6312@gmail.com',
      to: 'hetshah6315@gmail.com',
      subject: 'Test Email',
      text: 'This is a test email.'
    });

    console.log("Email sent successfully:", info.messageId);
  } catch (err) {
    console.error("Test failed:", err);
  }
}

test();
