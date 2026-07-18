import { prisma } from './prisma.js';
export async function seedDatabase() {
    const [userCount, partnerCount, venueCount] = await Promise.all([
        prisma.user.count(),
        prisma.partner.count(),
        prisma.venue.count(),
    ]);
    if (userCount > 0 || partnerCount > 0 || venueCount > 0) {
        console.log("Database already contains data (Users, Partners, or Venues). Skipping seeding to prevent data loss.");
        return;
    }
    console.log("Seeding database with matching reference mock data...");
    // 1. Create Partners
    const partner1 = await prisma.partner.create({
        data: {
            phone_number: "+919876543210",
            kyc_status: "pending",
            plan_tier: "premium",
            total_earnings: 12500.00
        }
    });
    const partner2 = await prisma.partner.create({
        data: {
            phone_number: "+919988776655",
            kyc_status: "verified",
            plan_tier: "free",
            total_earnings: 4200.00
        }
    });
    const partner3 = await prisma.partner.create({
        data: {
            phone_number: "+919123456789",
            kyc_status: "unverified",
            plan_tier: "free",
            total_earnings: 0.00
        }
    });
    // 2. Create exact Users from screenshot with custom UUIDs to align short IDs
    const user1 = await prisma.user.create({
        data: {
            user_id: "c8edfdee-0000-0000-0000-000000000000",
            phone_number: "+91 90000 00003",
            name: "Amit Kumar",
            email: "amit.kumar@outlook.com",
            status: "Active",
            total_bookings: 0,
            total_spend: 0.00
        }
    });
    const user2 = await prisma.user.create({
        data: {
            user_id: "d90545d5-0000-0000-0000-000000000000",
            phone_number: "+91 90000 00002",
            name: "Priya Patel",
            email: "priya.patel@yahoo.com",
            status: "Active",
            total_bookings: 2,
            total_spend: 1800.00
        }
    });
    const user3 = await prisma.user.create({
        data: {
            user_id: "761ef486-0000-0000-0000-000000000000",
            phone_number: "+91 90000 00001",
            name: "Rahul Sharma",
            email: "rahul.sharma@gmail.com",
            status: "Active",
            total_bookings: 5,
            total_spend: 3500.00
        }
    });
    const user4 = await prisma.user.create({
        data: {
            user_id: "d44a9b10-0000-0000-0000-000000000000",
            phone_number: "+91 90000 00004",
            name: "Sneha Reddy",
            email: "sneha.reddy@gmail.com",
            status: "Inactive",
            total_bookings: 0,
            total_spend: 0.00
        }
    });
    const user5 = await prisma.user.create({
        data: {
            user_id: "b7c1d2e3-0000-0000-0000-000000000000",
            phone_number: "+91 90000 00005",
            name: "Vikram Singh",
            email: "vikram.singh@icloud.com",
            status: "Blocked",
            total_bookings: 0,
            total_spend: 0.00
        }
    });
    // 3. Create Venues
    const venue1 = await prisma.venue.create({
        data: {
            partner_id: partner2.partner_id,
            name: "Downtown Football Arena",
            sport_types: ["Football", "Futsal"],
            status: "listed",
            base_price: 1500.00,
            avg_rating: 4.5,
            amenities: ["Wi-Fi", "Parking", "Showers", "Lockers", "Flood Lights"],
            images: [
                "https://images.unsplash.com/photo-1508098682722-e99c43a406b2?w=800",
                "https://images.unsplash.com/photo-1529900748604-07564a03e7a6?w=800"
            ],
            address: "123 Sports Drive, Sector 62, Noida, UP 201301",
            contact_phone: "+91 98765 43210"
        }
    });
    const venue2 = await prisma.venue.create({
        data: {
            partner_id: partner2.partner_id,
            name: "Smash Badminton Center",
            sport_types: ["Badminton"],
            status: "listed",
            base_price: 400.00,
            avg_rating: 4.8,
            amenities: ["Parking", "Lockers", "Drinks"],
            images: [
                "https://images.unsplash.com/photo-1518063319789-7217e6706b04?w=800"
            ],
            address: "456 Shuttle Court, Indiranagar, Bengaluru, KA 560038",
            contact_phone: "+91 80976 54321"
        }
    });
    const venue3 = await prisma.venue.create({
        data: {
            partner_id: partner1.partner_id,
            name: "Grand Tennis Club",
            sport_types: ["Tennis"],
            status: "unlisted",
            base_price: 800.00,
            avg_rating: 0.0,
            amenities: ["Wi-Fi", "Parking", "Showers"],
            images: [
                "https://images.unsplash.com/photo-1536122985607-4fe00b283652?w=800"
            ],
            address: "789 Baseline Court, Bandra West, Mumbai, MH 400050",
            contact_phone: "+91 70123 45678"
        }
    });
    // 4. Create Slots
    const dates = [
        new Date(),
        new Date(Date.now() + 24 * 60 * 60 * 1000),
        new Date(Date.now() + 2 * 24 * 60 * 60 * 1000)
    ];
    const slotsData = [];
    const startTimes = ["06:00", "07:00", "08:00", "17:00", "18:00", "19:00", "20:00"];
    for (const date of dates) {
        for (const st of startTimes) {
            const parts = st.split(":");
            const endHour = Number(parts[0]) + 1;
            const et = `${endHour < 10 ? '0' : ''}${endHour}:00`;
            slotsData.push({
                venue_id: venue1.venue_id,
                date: date,
                start_time: st,
                end_time: et,
                price: venue1.base_price,
                status: "available"
            });
            slotsData.push({
                venue_id: venue2.venue_id,
                date: date,
                start_time: st,
                end_time: et,
                price: venue2.base_price,
                status: "available"
            });
        }
    }
    const createdSlots = [];
    for (const s of slotsData) {
        const created = await prisma.slot.create({ data: s });
        createdSlots.push(created);
    }
    // 5. Create some Bookings and Transactions
    const slotToBook1 = createdSlots[3];
    const booking1 = await prisma.booking.create({
        data: {
            user_id: user3.user_id, // Rahul Sharma
            venue_id: venue1.venue_id,
            slot_id: slotToBook1.slot_id,
            status: "CONFIRMED",
            payment_mode: "card",
            eticket_code: "APV-2026-A2B3C4",
            convenience_fee: 60.00,
            commission_amount: 45.00,
            gst_amount: 8.10,
            partner_amount: 1446.90,
            online_amount: 1560.00,
            venue_amount: 0.00
        }
    });
    await prisma.slot.update({
        where: { slot_id: slotToBook1.slot_id },
        data: { status: "booked" }
    });
    await prisma.transaction.create({
        data: {
            booking_id: booking1.booking_id,
            razorpay_order_id: "order_mock_111",
            razorpay_payment_id: "pay_mock_111",
            txn_type: "capture",
            txn_status: "success",
            amount: 1560.00
        }
    });
    const slotToBook2 = createdSlots[20];
    const booking2 = await prisma.booking.create({
        data: {
            user_id: user2.user_id, // Priya Patel
            venue_id: venue2.venue_id,
            slot_id: slotToBook2.slot_id,
            status: "CONFIRMED",
            payment_mode: "pay_at_venue",
            eticket_code: "APV-2026-X9Y8Z7",
            convenience_fee: 0.00,
            commission_amount: 12.00,
            gst_amount: 2.16,
            partner_amount: 385.84,
            online_amount: 120.00,
            venue_amount: 280.00
        }
    });
    await prisma.slot.update({
        where: { slot_id: slotToBook2.slot_id },
        data: { status: "booked" }
    });
    await prisma.transaction.create({
        data: {
            booking_id: booking2.booking_id,
            razorpay_order_id: "order_mock_222",
            razorpay_payment_id: "pay_mock_222",
            txn_type: "capture",
            txn_status: "success",
            amount: 120.00
        }
    });
    // 6. Create Partner KYC Documents
    await prisma.partnerDocument.create({
        data: {
            partner_id: partner1.partner_id,
            document_type: "gst_certificate",
            file_url: "https://mock-s3-bucket.s3.amazonaws.com/kyc/gst_p1.pdf",
            status: "pending"
        }
    });
    await prisma.partnerDocument.create({
        data: {
            partner_id: partner1.partner_id,
            document_type: "pan_card",
            file_url: "https://mock-s3-bucket.s3.amazonaws.com/kyc/pan_p1.jpg",
            status: "pending"
        }
    });
    await prisma.partnerDocument.create({
        data: {
            partner_id: partner2.partner_id,
            document_type: "gst_certificate",
            file_url: "https://mock-s3-bucket.s3.amazonaws.com/kyc/gst_p2.pdf",
            status: "verified"
        }
    });
    // 7. Create a Dispute
    await prisma.dispute.create({
        data: {
            booking_id: booking2.booking_id,
            raised_by: "user",
            status: "open",
            details: "The host did not open the badminton court on time. I waited 20 minutes."
        }
    });
    // 8. Create some Coupons
    await prisma.coupon.create({
        data: {
            code: "WELCOME100",
            discount_type: "flat",
            discount_value: 100.00,
            min_order_value: 500.00,
            usage_limit: 1000,
            valid_from: new Date(),
            valid_until: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
        }
    });
    await prisma.coupon.create({
        data: {
            code: "SUMMER20",
            discount_type: "percent",
            discount_value: 20.00,
            max_discount: 300.00,
            min_order_value: 300.00,
            usage_limit: 500,
            valid_from: new Date(),
            valid_until: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000)
        }
    });
    console.log("Mock data seeding completed successfully.");
}
