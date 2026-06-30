

async function test() {
  console.log("=== API BOOKING TEST ===");
  
  // 1. Get OTP
  const phone = "9876543210";
  const reqOtp = await fetch("http://localhost:4000/api/auth/request-otp", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ phoneNumber: phone })
  });
  const otpRes = await reqOtp.json();
  console.log("OTP Res:", otpRes);

  // 2. Verify OTP to get token
  const verify = await fetch("http://localhost:4000/api/auth/verify-otp", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ phoneNumber: phone, otp: "123456", role: "user" })
  });
  const verifyRes = await verify.json();
  console.log("Verify Res:", verifyRes);
  const token = verifyRes.data.accessToken;

  // 3. Get Venues
  const venuesReq = await fetch("http://localhost:4000/api/venues", {
    headers: { "Authorization": `Bearer ${token}` }
  });
  const venuesRes = await venuesReq.json();
  console.log("Venues:", venuesRes.data.map(v => `${v.venue_id}: ${v.name}`));
  const venueId = venuesRes.data[0].venue_id;

  // 4. Get slots
  const slotsReq = await fetch(`http://localhost:4000/api/venues/${venueId}/slots?date=2026-06-21`, {
    headers: { "Authorization": `Bearer ${token}` }
  });
  const slotsRes = await slotsReq.json();
  const availableSlots = slotsRes.data.filter(s => s.status === 'available');
  console.log("Available Slots count:", availableSlots.length);
  if (availableSlots.length === 0) {
    console.log("No available slots found!");
    return;
  }
  const slotId = availableSlots[0].slot_id;
  console.log("Using slotId:", slotId);

  // 5. Try creating a booking
  const bookingReq = await fetch("http://localhost:4000/api/bookings", {
    method: "POST",
    headers: { 
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`
    },
    body: JSON.stringify({
      venueId: venueId,
      slotId: slotId,
      paymentMode: "pay_at_venue"
    })
  });
  const bookingRes = await bookingReq.json();
  console.log("Booking Response status:", bookingReq.status);
  console.log("Booking Response body:", JSON.stringify(bookingRes, null, 2));
}

test().catch(console.error);
