// APOV Admin Panel core application client logic

const token = localStorage.getItem('adminToken');
const adminEmail = localStorage.getItem('adminEmail');

// Auth Check
if (!token) {
    window.location.href = 'login.html';
}

document.getElementById('sidebarEmail').textContent = adminEmail || 'admin@athelete.pov';

// Active tab tracking
let activeTab = 'dashboard';
let currentKycDocId = null;
let currentBookingId = null;
let currentBookingVenueId = null;
let editingCouponId = null;

// User table sorting & multi-selection state
let loadedUsers = [];
let userSortField = '';
let userSortAsc = true;
let selectedUserIds = new Set();
let currentInspectedUser = null;

// Charts instances
let userGrowthChart = null;
let revenueTrendChart = null;
let topCitiesChart = null;

// Toggle Sidebar Nav Group
function toggleNavGroup(element) {
    const appLayout = document.getElementById('appLayout');
    if (appLayout && appLayout.classList.contains('collapsed')) {
        appLayout.classList.remove('collapsed');
    }
    const group = element.closest('.nav-group');
    if (group) {
        group.classList.toggle('expanded');
    }
}

const validTabs = [
    'dashboard', 'users', 'milestones', 'rewards', 'partners', 
    'kyc', 'venues', 'approvals', 'featured-venues', 'bookings', 
    'refunds', 'reassignment', 'finance', 'settlements', 'pav-ledger', 
    'commissions', 'tournaments', 'registrations', 'coupons', 
    'notifications', 'banners', 'reviews', 'chat-monitoring', 
    'reports', 'exports', 'settings', 'roles', 'audit-logs',
    'demand', 'disputes', 'broadcasts'
];

// Page startup
window.addEventListener('DOMContentLoaded', () => {
    // Restore theme from localStorage
    const savedTheme = localStorage.getItem('theme') || 'dark';
    document.documentElement.setAttribute('data-theme', savedTheme);
    const themeIcon = document.querySelector('#themeToggle .icon');
    if (themeIcon) {
        themeIcon.textContent = savedTheme === 'dark' ? '🌙' : '☀️';
    }

    // Load initial tab from URL hash if available
    const hash = window.location.hash.substring(1);
    if (hash && validTabs.includes(hash)) {
        switchTab(hash);
    } else {
        switchTab('dashboard');
    }
});

// Watch for manual URL hash updates or navigation changes
window.addEventListener('hashchange', () => {
    const hash = window.location.hash.substring(1);
    if (hash && validTabs.includes(hash) && activeTab !== hash) {
        switchTab(hash);
    }
});

// Helper for HTTP requests
async function apiCall(endpoint, method = 'GET', body = null) {
    const headers = {
        'Authorization': `Bearer ${token}`,
        'X-Admin-Role': 'admin',
        'Content-Type': 'application/json'
    };

    const options = { method, headers };
    if (body) {
        options.body = JSON.stringify(body);
    }

    try {
        const response = await fetch(endpoint, options);
        if (response.status === 401 || response.status === 403) {
            // Token expired or invalid
            localStorage.clear();
            window.location.href = 'login.html';
            return;
        }

        const json = await response.json();
        if (!json.success) {
            throw new Error(json.error?.message || 'API request failed');
        }
        return json.data;
    } catch (err) {
        console.error(`API Call failed on ${endpoint}:`, err);
        alert(`Error: ${err.message}`);
        throw err;
    }
}

// Tab Swapper
function switchTab(tabId) {
    activeTab = tabId;
    if (window.location.hash !== `#${tabId}`) {
        window.location.hash = tabId;
    }
    
    // Clear search bar on tab change
    document.getElementById('headerSearch').value = '';

    // Update active class on nav links
    document.querySelectorAll('.nav-item, .nav-sub-item').forEach(link => {
        link.classList.remove('active');
        if (link.getAttribute('href') === `#${tabId}`) {
            link.classList.add('active');
            
            // Auto-expand group parent if it exists
            const parentGroup = link.closest('.nav-group');
            if (parentGroup) {
                parentGroup.classList.add('expanded');
            }
        }
    });

    // Toggle active section
    document.querySelectorAll('.tab-section').forEach(section => {
        section.classList.remove('active');
    });
    
    const targetSection = document.getElementById(`tab-${tabId}`);
    if (targetSection) {
        targetSection.classList.add('active');
    }

    // Set header title
    let formattedTitle = tabId.charAt(0).toUpperCase() + tabId.slice(1);
    if (tabId === 'partners') formattedTitle = 'Partners List';
    else if (tabId === 'demand') formattedTitle = 'Surge Pricing';
    else if (tabId === 'audit-logs') formattedTitle = 'Audit Logs';
    else if (tabId === 'roles') formattedTitle = 'Roles & Permissions';
    else if (tabId === 'reviews') formattedTitle = 'Reviews & Ratings';
    else if (tabId === 'broadcasts') formattedTitle = 'FCM Broadcast Logs';
    else if (tabId === 'milestones') formattedTitle = 'Milestones Config';
    else if (tabId === 'rewards') formattedTitle = 'Rewards Manager';
    else if (tabId === 'kyc') formattedTitle = 'KYC Document Verification';
    else if (tabId === 'approvals') formattedTitle = 'Venue Approvals Queue';
    else if (tabId === 'featured-venues') formattedTitle = 'Featured Venues Priority';
    else if (tabId === 'refunds') formattedTitle = 'Refund Center';
    else if (tabId === 'reassignment') formattedTitle = 'Slot Reassignment Tool';
    else if (tabId === 'commissions') formattedTitle = 'Commission Manager';
    else if (tabId === 'registrations') formattedTitle = 'Tournament Registrations';
    else if (tabId === 'chat-monitoring') formattedTitle = 'Chat Compliance Monitoring';
    else if (tabId === 'reports') formattedTitle = 'Reports & Analytics';
    else if (tabId === 'exports') formattedTitle = 'Data Export Center';
    else if (tabId === 'pav-ledger') formattedTitle = 'PAV Outstanding Ledger';
    
    document.getElementById('viewTitle').textContent = formattedTitle;

    // Fetch tab data
    loadTabData(tabId);
}

// Fetcher Route Map
function loadTabData(tabId) {
    switch (tabId) {
        case 'dashboard':
            loadDashboardData();
            break;
        case 'users':
            loadUsersData();
            break;
        case 'milestones':
            loadMilestonesData();
            break;
        case 'rewards':
            loadRewardsData();
            break;
        case 'partners':
            loadPartnersData();
            break;
        case 'kyc':
            loadKycData();
            break;
        case 'venues':
            loadVenuesData();
            break;
        case 'approvals':
            loadApprovalsData();
            break;
        case 'featured-venues':
            loadFeaturedVenuesData();
            break;
        case 'bookings':
            loadBookingsData();
            break;
        case 'refunds':
            loadRefundsData();
            break;
        case 'reassignment':
            loadReassignmentData();
            break;
        case 'finance':
            loadFinanceData();
            break;
        case 'settlements':
            loadSettlementsData();
            break;
        case 'pav-ledger':
            loadTransactionsLedger(); // Reuse transactions table
            break;
        case 'commissions':
            loadCommissionsData();
            break;
        case 'tournaments':
            loadTournamentsData();
            break;
        case 'registrations':
            loadRegistrationsData();
            break;
        case 'coupons':
            loadCouponsData();
            break;
        case 'notifications':
            loadNotificationsData();
            break;
        case 'banners':
            loadBannersData();
            break;
        case 'reviews':
            loadReviewsData();
            break;
        case 'chat-monitoring':
            loadChatMonitoringData();
            break;
        case 'reports':
            loadReportsData();
            break;
        case 'exports':
            loadExportsData();
            break;
        case 'settings':
            loadSettingsData();
            break;
        case 'roles':
            loadRolesData();
            break;
        case 'audit-logs':
            loadAuditLogsData();
            break;
    }
}

// 1. DASHBOARD TAB
async function loadDashboardData() {
    try {
        const stats = await apiCall('/api/admin/stats');
        if (!stats) return;

        if (document.getElementById('kpi-users')) {
            document.getElementById('kpi-users').textContent = stats.users;
        }
        if (document.getElementById('kpi-partners')) {
            document.getElementById('kpi-partners').textContent = stats.partners;
        }
        if (document.getElementById('kpi-venues')) {
            document.getElementById('kpi-venues').textContent = stats.venues;
        }
        if (document.getElementById('kpi-bookings')) {
            document.getElementById('kpi-bookings').textContent = stats.bookings;
        }
        if (document.getElementById('kpi-revenue')) {
            document.getElementById('kpi-revenue').textContent = `₹${stats.totalRevenue.toFixed(2)}`;
        }
        if (document.getElementById('kpi-earnings')) {
            document.getElementById('kpi-earnings').textContent = `₹${stats.totalCommission.toFixed(2)}`;
        }

        if (document.getElementById('kpi-today-bookings')) {
            document.getElementById('kpi-today-bookings').textContent = stats.todayBookings || '0';
        }
        if (document.getElementById('kpi-monthly-revenue')) {
            document.getElementById('kpi-monthly-revenue').textContent = `₹${(stats.monthlyRevenue || 0).toFixed(2)}`;
        }
        if (document.getElementById('kpi-pending-kyc')) {
            document.getElementById('kpi-pending-kyc').textContent = stats.pendingKycApprovals || '0';
        }
        if (document.getElementById('kpi-active-tournaments')) {
            document.getElementById('kpi-active-tournaments').textContent = stats.activeTournaments || '0';
        }
        if (document.getElementById('kpi-pending-refunds')) {
            document.getElementById('kpi-pending-refunds').textContent = stats.pendingRefunds || '0';
        }
        if (document.getElementById('kpi-outstanding-pav')) {
            document.getElementById('kpi-outstanding-pav').textContent = `₹${(stats.outstandingPavAmount || 0).toFixed(2)}`;
        }

        // Load Top Venues Table
        const venues = await apiCall('/api/admin/venues');
        const sorted = venues.slice(0, 5).sort((a, b) => b._count.bookings - a._count.bookings);
        const tbody = document.querySelector('#topVenuesTable tbody');
        tbody.innerHTML = '';

        if (sorted.length === 0) {
            tbody.innerHTML = `<tr><td colspan="4" class="text-center">No venues registered yet</td></tr>`;
            return;
        }

        sorted.forEach(v => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td><strong>${v.name}</strong></td>
                <td>${v.sport_types.join(', ')}</td>
                <td>₹${Number(v.base_price).toFixed(2)}</td>
                <td>★ ${Number(v.avg_rating).toFixed(1)}</td>
            `;
            tbody.appendChild(row);
        });

        // Initialize/Render Chart.js charts
        renderDashboardCharts();

    } catch (err) {
        console.error(err);
    }
}

// 2. USERS TAB
async function loadUsersData() {
    try {
        const users = await apiCall('/api/admin/users');
        loadedUsers = users;
        selectedUserIds.clear();
        
        // Reset select-all box
        const selectAllBox = document.getElementById('selectAllUsers');
        if (selectAllBox) selectAllBox.checked = false;

        renderUsersTable(users);
    } catch (err) {
        console.error(err);
    }
}

// 3. PARTNERS & KYC TAB
async function loadPartnersData() {
    try {
        // Load All Partners
        const partners = await apiCall('/api/admin/partners');
        const tbody = document.querySelector('#partnersTable tbody');
        tbody.innerHTML = '';

        if (partners.length === 0) {
            tbody.innerHTML = `<tr><td colspan="7" class="text-center">No host partners registered yet</td></tr>`;
        } else {
            partners.forEach(p => {
                const date = new Date(p.created_at).toLocaleDateString('en-IN');
                let kycBadgeClass = 'neutral';
                if (p.kyc_status === 'verified') kycBadgeClass = 'success';
                if (p.kyc_status === 'pending') kycBadgeClass = 'pending';
                if (p.kyc_status === 'rejected') kycBadgeClass = 'danger';

                const row = document.createElement('tr');
                row.innerHTML = `
                    <td><code>${p.partner_id.substring(0, 8)}</code></td>
                    <td>${p.phone_number}</td>
                    <td><span class="badge ${kycBadgeClass}">${p.kyc_status}</span></td>
                    <td><span class="badge neutral">${p.plan_tier}</span></td>
                    <td>₹${Number(p.total_earnings).toFixed(2)}</td>
                    <td>${date}</td>
                    <td>
                        <div style="display: flex; gap: 5px;">
                            <button class="btn-action text-secondary" onclick="openPartnerEditModal('${p.partner_id}', '${escapeHtml(p.phone_number)}', '${p.kyc_status}', '${p.plan_tier}', ${Number(p.total_earnings)})">Edit</button>
                            <button class="btn-action text-danger" onclick="deletePartner('${p.partner_id}')">Delete</button>
                        </div>
                    </td>
                `;
                tbody.appendChild(row);
            });
        }

        // Load Pending KYC Queue
        const kycDocs = await apiCall('/api/admin/kyc/pending');
        const queueTbody = document.querySelector('#kycQueueTable tbody');
        queueTbody.innerHTML = '';

        if (kycDocs.length === 0) {
            queueTbody.innerHTML = `<tr><td colspan="5" class="text-center">No pending items in queue</td></tr>`;
            return;
        }

        kycDocs.forEach(d => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${d.doc_id.substring(0, 8)}</code></td>
                <td><code>${d.partner_id.substring(0, 8)}</code> (${d.partner.phone_number})</td>
                <td><strong>${d.document_type.toUpperCase().replace('_', ' ')}</strong></td>
                <td><span class="badge pending">${d.status}</span></td>
                <td>
                    <button class="btn-action text-secondary" onclick="openKycInspection('${d.doc_id}', '${d.file_url}')">Inspect File</button>
                </td>
            `;
            queueTbody.appendChild(row);
        });

    } catch (err) {
        console.error(err);
    }
}

function openKycInspection(docId, fileUrl) {
    currentKycDocId = docId;
    document.getElementById('kycDocUrl').textContent = fileUrl;
    document.getElementById('kycDocLink').href = fileUrl;
    document.getElementById('kycRejectionNote').value = '';
    
    openModal('kycModal');
}

async function submitKycResolution(status) {
    const rejectionNote = document.getElementById('kycRejectionNote').value;
    if (status === 'rejected' && !rejectionNote.trim()) {
        alert("Please provide a rejection note details explaining why the document is rejected.");
        return;
    }

    try {
        await apiCall(`/api/admin/kyc/document/${currentKycDocId}`, 'PATCH', {
            status,
            rejection_note: rejectionNote
        });
        closeModal('kycModal');
        loadPartnersData();
    } catch (err) {
        console.error(err);
    }
}

// 4. VENUES TAB
async function loadVenuesData() {
    try {
        const venues = await apiCall('/api/admin/venues');
        const tbody = document.querySelector('#venuesTable tbody');
        tbody.innerHTML = '';

        if (venues.length === 0) {
            tbody.innerHTML = `<tr><td colspan="8" class="text-center">No venues listed yet</td></tr>`;
            return;
        }

        venues.forEach(v => {
            let statusBadge = 'neutral';
            if (v.status === 'listed') statusBadge = 'success';
            if (v.status === 'suspended') statusBadge = 'danger';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td><strong>${v.name}</strong></td>
                <td>${v.partner.phone_number}</td>
                <td>${v.sport_types.join(', ')}</td>
                <td>₹${Number(v.base_price).toFixed(2)}</td>
                <td>★ ${Number(v.avg_rating).toFixed(1)}</td>
                <td><span class="badge ${statusBadge}">${v.status}</span></td>
                <td>
                    <input type="checkbox" class="featured-toggle" ${v.status === 'listed' ? '' : 'disabled'} onchange="toggleFeatured('${v.venue_id}', this.checked)">
                </td>
                <td>
                    <div style="display: flex; gap: 5px; flex-wrap: wrap;">
                        <button class="btn-action text-success" ${v.status === 'listed' ? 'disabled' : ''} onclick="updateVenueStatus('${v.venue_id}', 'listed')">Approve</button>
                        <button class="btn-action text-danger" ${v.status === 'suspended' ? 'disabled' : ''} onclick="updateVenueStatus('${v.venue_id}', 'suspended')">Suspend</button>
                        <button class="btn-action text-secondary" onclick="openVenueEditModal('${v.venue_id}', '${v.partner_id}', '${escapeHtml(v.name)}', '${escapeHtml(v.sport_types.join(', '))}', ${Number(v.base_price)}, '${v.status}')">Edit</button>
                        <button class="btn-action text-danger" onclick="deleteVenue('${v.venue_id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

async function updateVenueStatus(venueId, status) {
    try {
        await apiCall(`/api/admin/venues/${venueId}/status`, 'PATCH', { status });
        loadVenuesData();
    } catch (err) {
        console.error(err);
    }
}

async function toggleFeatured(venueId, checked) {
    try {
        await apiCall(`/api/admin/venues/${venueId}/feature`, 'PATCH', { isFeatured: checked });
        alert(`Venue feature placement updated successfully.`);
    } catch (err) {
        console.error(err);
    }
}

// 5. BOOKINGS TAB
async function loadBookingsData() {
    try {
        const bookings = await apiCall('/api/admin/bookings');
        const tbody = document.querySelector('#bookingsTable tbody');
        tbody.innerHTML = '';

        if (bookings.length === 0) {
            tbody.innerHTML = `<tr><td colspan="8" class="text-center">No bookings placed yet</td></tr>`;
            return;
        }

        bookings.forEach(b => {
            const date = new Date(b.slot.date).toLocaleDateString('en-IN');
            let statusClass = 'neutral';
            if (b.status === 'CONFIRMED') statusClass = 'success';
            if (b.status === 'CANCELLED') statusClass = 'danger';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${b.eticket_code}</code></td>
                <td>${b.user.email || '-'} (${b.user.phone_number})</td>
                <td>${b.venue.name}</td>
                <td>${date} <br><small>${b.slot.start_time} - ${b.slot.end_time}</small></td>
                <td>₹${Number(b.online_amount).toFixed(2)}</td>
                <td>₹${Number(b.venue_amount).toFixed(2)}</td>
                <td><span class="badge ${statusClass}">${b.status}</span></td>
                <td>
                    <div style="display: flex; gap: 5px; flex-wrap: wrap;">
                        <button class="btn-action text-secondary" ${b.status !== 'CONFIRMED' ? 'disabled' : ''} onclick="openReassignModal('${b.booking_id}', '${b.venue_id}')">Reassign</button>
                        <button class="btn-action text-danger" ${b.status !== 'CONFIRMED' ? 'disabled' : ''} onclick="cancelBooking('${b.booking_id}')">Cancel</button>
                        <button class="btn-action text-secondary" onclick="openBookingEditModal('${b.booking_id}', '${b.user_id}', '${b.venue_id}', '${b.slot_id}', '${b.payment_mode}', ${Number(b.online_amount)}, ${Number(b.venue_amount)}, '${b.status}')">Edit</button>
                        <button class="btn-action text-danger" onclick="deleteBooking('${b.booking_id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

async function cancelBooking(bookingId) {
    if (!confirm("Are you sure you want to cancel this booking? This will issue an automated refund and reopen the slot.")) return;
    try {
        await apiCall(`/api/admin/bookings/${bookingId}/cancel`, 'PATCH');
        loadBookingsData();
    } catch (err) {
        console.error(err);
    }
}

async function openReassignModal(bookingId, venueId) {
    currentBookingId = bookingId;
    currentBookingVenueId = venueId;

    try {
        // Fetch all slots of this venue
        const slots = await apiCall(`/api/admin/venues/${venueId}/slots`);
        const select = document.getElementById('reassignSlotSelect');
        select.innerHTML = '<option value="">Select target slot...</option>';

        const available = slots.filter(s => s.status === 'available');
        if (available.length === 0) {
            select.innerHTML = '<option value="">No other slots available</option>';
        } else {
            available.forEach(s => {
                const date = new Date(s.date).toLocaleDateString('en-IN');
                const option = document.createElement('option');
                option.value = s.slot_id;
                option.textContent = `${date} @ ${s.start_time} - ${s.end_time} (₹${Number(s.price).toFixed(2)})`;
                select.appendChild(option);
            });
        }

        openModal('reassignModal');
    } catch (err) {
        console.error(err);
    }
}

async function submitReassignment() {
    const newSlotId = document.getElementById('reassignSlotSelect').value;
    if (!newSlotId) {
        alert("Please select a target slot.");
        return;
    }

    try {
        await apiCall(`/api/admin/bookings/${currentBookingId}/reassign`, 'PATCH', { newSlotId });
        closeModal('reassignModal');
        loadBookingsData();
        alert("Slot reassigned successfully.");
    } catch (err) {
        console.error(err);
    }
}

// 6. FINANCE TAB
async function loadFinanceData() {
    try {
        const txns = await apiCall('/api/admin/transactions');
        const tbody = document.querySelector('#transactionsTable tbody');
        tbody.innerHTML = '';

        if (txns.length === 0) {
            tbody.innerHTML = `<tr><td colspan="8" class="text-center">No transactions registered yet</td></tr>`;
            return;
        }

        txns.forEach(t => {
            const date = new Date(t.created_at).toLocaleDateString('en-IN');
            let statusClass = 'neutral';
            if (t.txn_status === 'success') statusClass = 'success';
            if (t.txn_status === 'failed') statusClass = 'danger';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${t.txn_id.substring(0, 8)}</code></td>
                <td><code>${t.booking.eticket_code}</code></td>
                <td><code>${t.razorpay_order_id}</code></td>
                <td><code>${t.razorpay_payment_id || '-'}</code></td>
                <td><strong>${t.txn_type.toUpperCase()}</strong></td>
                <td><span class="badge ${statusClass}">${t.txn_status}</span></td>
                <td>₹${Number(t.amount).toFixed(2)}</td>
                <td>${date}</td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

// 7. COUPONS TAB
async function loadCouponsData() {
    try {
        const coupons = await apiCall('/api/admin/coupons');
        const tbody = document.querySelector('#couponsTable tbody');
        tbody.innerHTML = '';

        if (coupons.length === 0) {
            tbody.innerHTML = `<tr><td colspan="9" class="text-center">No coupons created yet</td></tr>`;
            return;
        }

        coupons.forEach(c => {
            const from = new Date(c.valid_from).toLocaleDateString('en-IN');
            const until = new Date(c.valid_until).toLocaleDateString('en-IN');
            
            let badgeClass = 'success';
            if (!c.is_active) badgeClass = 'danger';

            const valStr = c.discount_type === 'percent' ? `${Number(c.discount_value).toFixed(0)}%` : `₹${Number(c.discount_value).toFixed(2)}`;

            const row = document.createElement('tr');
            row.innerHTML = `
                <td><strong>${c.code}</strong></td>
                <td><span class="badge neutral">${c.discount_type}</span></td>
                <td>${valStr}</td>
                <td>${c.max_discount ? '₹' + Number(c.max_discount).toFixed(2) : '-'}</td>
                <td>₹${Number(c.min_order_value).toFixed(2)}</td>
                <td>${c.usage_limit}</td>
                <td><span class="badge ${badgeClass}">${c.is_active ? 'Active' : 'Expired'}</span></td>
                <td>${from} - ${until}</td>
                <td>
                    <div style="display: flex; gap: 5px;">
                        <button class="btn-action text-secondary" onclick="openCouponEditModal('${c.coupon_id}', '${c.code}', '${c.discount_type}', ${c.discount_value}, ${c.max_discount || ''}, ${c.min_order_value}, ${c.usage_limit}, '${c.valid_from.substring(0, 10)}', '${c.valid_until.substring(0, 10)}')">Edit</button>
                        <button class="btn-action text-danger" onclick="deleteCoupon('${c.coupon_id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

function openCouponModal() {
    editingCouponId = null;
    document.getElementById('couponForm').reset();
    document.getElementById('coupon-code').disabled = false;
    openModal('couponModal');
}

function openCouponEditModal(id, code, type, value, max, min, limit, from, until) {
    editingCouponId = id;
    document.getElementById('coupon-code').value = code;
    document.getElementById('coupon-code').disabled = true;
    document.getElementById('coupon-type').value = type;
    document.getElementById('coupon-value').value = value;
    document.getElementById('coupon-max-disc').value = max || '';
    document.getElementById('coupon-min-order').value = min;
    document.getElementById('coupon-limit').value = limit;
    document.getElementById('coupon-from').value = from;
    document.getElementById('coupon-until').value = until;
    
    openModal('couponModal');
}

async function submitCoupon(e) {
    e.preventDefault();
    const code = document.getElementById('coupon-code').value;
    const discount_type = document.getElementById('coupon-type').value;
    const discount_value = Number(document.getElementById('coupon-value').value);
    const max_discount = document.getElementById('coupon-max-disc').value ? Number(document.getElementById('coupon-max-disc').value) : undefined;
    const min_order_value = Number(document.getElementById('coupon-min-order').value);
    const usage_limit = Number(document.getElementById('coupon-limit').value);
    const valid_from = document.getElementById('coupon-from').value;
    const valid_until = document.getElementById('coupon-until').value;

    const payload = {
        code,
        discount_type,
        discount_value,
        max_discount,
        min_order_value,
        usage_limit,
        valid_from,
        valid_until
    };

    try {
        if (editingCouponId) {
            await apiCall(`/api/admin/coupons/${editingCouponId}`, 'PATCH', payload);
        } else {
            await apiCall('/api/admin/coupons', 'POST', payload);
        }
        closeModal('couponModal');
        loadCouponsData();
    } catch (err) {
        console.error(err);
    }
}

async function deleteCoupon(couponId) {
    if (!confirm("Are you sure you want to delete this coupon?")) return;
    try {
        await apiCall(`/api/admin/coupons/${couponId}`, 'DELETE');
        loadCouponsData();
    } catch (err) {
        console.error(err);
    }
}

// 8. NOTIFICATIONS TAB
async function loadNotificationsData() {
    try {
        const broadcasts = await apiCall('/api/admin/broadcasts');
        const tbody = document.querySelector('#broadcastsTable tbody');
        tbody.innerHTML = '';

        if (broadcasts.length === 0) {
            tbody.innerHTML = `<tr><td colspan="6" class="text-center">No broadcasts sent yet</td></tr>`;
            return;
        }

        broadcasts.forEach(b => {
            const date = new Date(b.sent_at).toLocaleString('en-IN');
            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${b.broadcast_id.substring(0, 8)}</code></td>
                <td><span class="badge neutral">${b.audience_type}</span></td>
                <td><strong>${b.title}</strong></td>
                <td>${b.body}</td>
                <td><span class="badge success">${b.status}</span></td>
                <td>${date}</td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

async function handleBroadcast(e) {
    e.preventDefault();
    const audience_type = document.getElementById('notif-cohort').value;
    const title = document.getElementById('notif-title').value;
    const body = document.getElementById('notif-body').value;

    try {
        await apiCall('/api/admin/broadcast', 'POST', { audience_type, title, body });
        document.getElementById('broadcastForm').reset();
        loadNotificationsData();
        alert("FCM Push broadcast dispatched successfully.");
    } catch (err) {
        console.error(err);
    }
}

// 9. DISPUTES TAB
async function loadDisputesData() {
    try {
        const disputes = await apiCall('/api/admin/disputes');
        const tbody = document.querySelector('#disputesTable tbody');
        tbody.innerHTML = '';

        if (disputes.length === 0) {
            tbody.innerHTML = `<tr><td colspan="7" class="text-center">No disputes raised yet</td></tr>`;
            return;
        }

        disputes.forEach(d => {
            let statusBadge = 'neutral';
            if (d.status === 'resolved') statusBadge = 'success';
            if (d.status === 'open') statusBadge = 'danger';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${d.dispute_id.substring(0, 8)}</code></td>
                <td><code>${d.booking.eticket_code}</code></td>
                <td><strong>${d.raised_by.toUpperCase()}</strong></td>
                <td>${d.details}</td>
                <td>${d.resolution || '-'}</td>
                <td><span class="badge ${statusBadge}">${d.status}</span></td>
                <td>
                    <div style="display: flex; gap: 5px; flex-wrap: wrap;">
                        <button class="btn-action text-success" ${d.status === 'resolved' ? 'disabled' : ''} onclick="resolveDispute('${d.dispute_id}', 'refund_user')">Refund & Resolve</button>
                        <button class="btn-action text-danger" ${d.status === 'resolved' ? 'disabled' : ''} onclick="resolveDispute('${d.dispute_id}', 'closed_no_action')">Close Case</button>
                        <button class="btn-action text-secondary" onclick="openDisputeEditModal('${d.dispute_id}', '${d.booking_id}', '${d.raised_by}', '${escapeHtml(d.details)}', '${d.status}')">Edit</button>
                        <button class="btn-action text-danger" onclick="deleteDispute('${d.dispute_id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

async function resolveDispute(disputeId, resolution) {
    if (!confirm(`Resolve this dispute with resolution "${resolution}"?`)) return;
    try {
        await apiCall(`/api/admin/disputes/${disputeId}/resolve`, 'PATCH', { resolution });
        loadDisputesData();
    } catch (err) {
        console.error(err);
    }
}

// 10. DEMAND (SURGE) TAB
async function loadDemandData() {
    try {
        const venues = await apiCall('/api/admin/venues');
        const select = document.getElementById('slotsVenueSelect');
        select.innerHTML = '<option value="">Select a venue...</option>';

        venues.forEach(v => {
            const option = document.createElement('option');
            option.value = v.venue_id;
            option.textContent = v.name;
            select.appendChild(option);
        });

        document.getElementById('slotsSection').classList.add('hidden');
    } catch (err) {
        console.error(err);
    }
}

async function loadVenueSlots(venueId) {
    if (!venueId) {
        document.getElementById('slotsSection').classList.add('hidden');
        return;
    }

    try {
        const slots = await apiCall(`/api/admin/venues/${venueId}/slots`);
        const tbody = document.querySelector('#slotsTable tbody');
        tbody.innerHTML = '';

        if (slots.length === 0) {
            tbody.innerHTML = `<tr><td colspan="6" class="text-center">No slots listed for this venue</td></tr>`;
            document.getElementById('slotsSection').classList.remove('hidden');
            return;
        }

        slots.forEach(s => {
            const date = new Date(s.date).toLocaleDateString('en-IN');
            
            let tagBadge = '';
            if (s.demand_tag) {
                tagBadge = `<span class="badge pending">${s.demand_tag}</span>`;
            }

            let statusClass = 'success';
            if (s.status !== 'available') statusClass = 'neutral';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td><input type="checkbox" class="slot-checkbox" value="${s.slot_id}"></td>
                <td>${date}</td>
                <td><strong>${s.start_time} - ${s.end_time}</strong></td>
                <td>₹${Number(s.price).toFixed(2)}</td>
                <td>${tagBadge || '-'}</td>
                <td><span class="badge ${statusClass}">${s.status}</span></td>
            `;
            tbody.appendChild(row);
        });

        document.getElementById('slotsSection').classList.remove('hidden');
    } catch (err) {
        console.error(err);
    }
}

async function applySurge() {
    const checkboxes = document.querySelectorAll('.slot-checkbox:checked');
    const slotIds = Array.from(checkboxes).map(c => c.value);
    const tag = document.getElementById('surgeTagSelect').value;

    if (slotIds.length === 0) {
        alert("Please select at least one slot to modify.");
        return;
    }

    try {
        await apiCall('/api/admin/slots/demand-tag', 'POST', { slotIds, tag });
        const select = document.getElementById('slotsVenueSelect');
        loadVenueSlots(select.value);
        alert("Surge tags applied successfully (+50% price).");
    } catch (err) {
        console.error(err);
    }
}

async function removeSurge() {
    const checkboxes = document.querySelectorAll('.slot-checkbox:checked');
    const slotIds = Array.from(checkboxes).map(c => c.value);

    if (slotIds.length === 0) {
        alert("Please select at least one slot to modify.");
        return;
    }

    try {
        await apiCall('/api/admin/slots/demand-tag', 'DELETE', { slotIds });
        const select = document.getElementById('slotsVenueSelect');
        loadVenueSlots(select.value);
        alert("Surge tags removed successfully (prices restored).");
    } catch (err) {
        console.error(err);
    }
}

// Global Modal Handlers
function openModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.add('active');
    }
}

function closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.classList.remove('active');
    }
}

// Theme toggler
function toggleTheme() {
    const currentTheme = document.documentElement.getAttribute('data-theme');
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    
    document.documentElement.setAttribute('data-theme', newTheme);
    localStorage.setItem('theme', newTheme);

    // Re-render charts to adapt color variables
    if (activeTab === 'dashboard') {
        renderDashboardCharts();
    }
}

// Logout
function logout() {
    localStorage.clear();
    window.location.href = 'login.html';
}

// Sidebar Toggle
function toggleSidebar() {
    const appLayout = document.getElementById('appLayout');
    if (appLayout) {
        appLayout.classList.toggle('collapsed');
    }
}

// Global Real-time Table Search Filter
function handleGlobalSearch(query) {
    const lower = query.toLowerCase().trim();
    
    // Target the active tab section container
    const activeSection = document.querySelector('.tab-section.active');
    if (!activeSection) return;

    // Find any standard tables in the section
    const tables = activeSection.querySelectorAll('.table-simple');
    if (tables.length === 0) return;

    tables.forEach(table => {
        const rows = table.querySelectorAll('tbody tr');
        rows.forEach(row => {
            const cells = row.querySelectorAll('td');
            // Skip indicator row
            if (cells.length <= 1) return;

            let isMatch = false;
            cells.forEach(cell => {
                if (cell.textContent.toLowerCase().includes(lower)) {
                    isMatch = true;
                }
            });

            if (isMatch || lower === '') {
                row.classList.remove('hidden');
            } else {
                row.classList.add('hidden');
            }
        });
    });
}

// ==========================================
// NEW HELPER FUNCTIONS FOR INTERACTIVE UI
// ==========================================

// Render User Growth, Revenue, and Top Cities charts
function renderDashboardCharts() {
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    const gridColor = isDark ? '#27272A' : '#E4E4E7';
    const textColor = isDark ? '#A1A1AA' : '#71717A';

    // 1. User Growth Chart
    const ctxUser = document.getElementById('userGrowthChart')?.getContext('2d');
    if (ctxUser) {
        if (userGrowthChart) userGrowthChart.destroy();
        userGrowthChart = new Chart(ctxUser, {
            type: 'line',
            data: {
                labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
                datasets: [{
                    label: 'Signups',
                    data: [2, 3, 5, 8, 12, 18],
                    borderColor: '#3B82F6',
                    backgroundColor: 'rgba(59, 130, 246, 0.1)',
                    tension: 0.4,
                    fill: true,
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false }
                },
                scales: {
                    x: {
                        grid: { display: false },
                        ticks: { color: textColor, font: { family: 'Inter' } }
                    },
                    y: {
                        grid: { color: gridColor },
                        ticks: { color: textColor, font: { family: 'Inter' }, stepSize: 5 }
                    }
                }
            }
        });
    }

    // 2. Revenue Trend Chart
    const ctxRev = document.getElementById('revenueTrendChart')?.getContext('2d');
    if (ctxRev) {
        if (revenueTrendChart) revenueTrendChart.destroy();
        revenueTrendChart = new Chart(ctxRev, {
            type: 'line',
            data: {
                labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
                datasets: [{
                    label: 'Revenue (₹)',
                    data: [1500, 2800, 1900, 3200, 4500, 6000, 5200],
                    borderColor: '#10B981',
                    backgroundColor: 'rgba(16, 185, 129, 0.1)',
                    tension: 0.4,
                    fill: true,
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false }
                },
                scales: {
                    x: {
                        grid: { display: false },
                        ticks: { color: textColor, font: { family: 'Inter' } }
                    },
                    y: {
                        grid: { color: gridColor },
                        ticks: { color: textColor, font: { family: 'Inter' } }
                    }
                }
            }
        });
    }

    // 3. Top Cities Chart
    const ctxCities = document.getElementById('topCitiesChart')?.getContext('2d');
    if (ctxCities) {
        if (topCitiesChart) topCitiesChart.destroy();
        topCitiesChart = new Chart(ctxCities, {
            type: 'doughnut',
            data: {
                labels: ['Bengaluru', 'Mumbai', 'Delhi NCR', 'Hyderabad'],
                datasets: [{
                    data: [40, 25, 20, 15],
                    backgroundColor: ['#3B82F6', '#10B981', '#F59E0B', '#EF4444'],
                    borderWidth: isDark ? 2 : 1,
                    borderColor: isDark ? '#111113' : '#FFFFFF'
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            color: textColor,
                            font: { family: 'Inter', size: 10 },
                            boxWidth: 12
                        }
                    }
                },
                cutout: '70%'
            }
        });
    }
}

// Render Users Table
function renderUsersTable(users) {
    const tbody = document.querySelector('#usersTable tbody');
    tbody.innerHTML = '';

    if (users.length === 0) {
        tbody.innerHTML = `<tr><td colspan="9" class="text-center">No athletes match the criteria</td></tr>`;
        return;
    }

    users.forEach(u => {
        const initials = u.name ? u.name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase() : 'U';
        const isChecked = selectedUserIds.has(u.user_id) ? 'checked' : '';
        let badgeClass = 'success';
        if (u.status === 'Inactive') badgeClass = 'neutral';
        if (u.status === 'Blocked') badgeClass = 'danger';

        const row = document.createElement('tr');
        row.className = 'user-row';
        row.style.cursor = 'pointer';

        // Row click opens the drawer
        row.addEventListener('click', (e) => {
            // Avoid triggering when clicking checkbox cell or actions column
            if (e.target.tagName !== 'INPUT' && !e.target.closest('td:first-child') && !e.target.closest('.btn-action')) {
                openUserDrawer(u);
            }
        });

        row.innerHTML = `
            <td style="padding: 10px 14px;"><input type="checkbox" class="user-checkbox" value="${u.user_id}" ${isChecked} onchange="toggleSelectUser('${u.user_id}', this.checked)"></td>
            <td>
                <div class="user-profile-cell">
                    <div class="avatar-circle theme-avatar">${initials}</div>
                    <span class="user-name-text" style="font-weight: 600;">${u.name || 'Anonymous'}</span>
                </div>
            </td>
            <td><code>${u.user_id.substring(0, 8)}</code></td>
            <td>${u.phone_number}</td>
            <td>${u.email || '-'}</td>
            <td class="text-right">${u.total_bookings}</td>
            <td class="text-right">₹${Number(u.total_spend).toFixed(2)}</td>
            <td><span class="badge ${badgeClass}">${u.status}</span></td>
            <td>
                <div style="display: flex; gap: 5px;">
                    <button class="btn-action text-secondary" onclick="openUserEditModal('${u.user_id}', '${escapeHtml(u.name || '')}', '${escapeHtml(u.email || '')}', '${escapeHtml(u.phone_number)}', '${u.status}')">Edit</button>
                    <button class="btn-action text-danger" onclick="deleteUser('${u.user_id}')">Delete</button>
                </div>
            </td>
        `;
        tbody.appendChild(row);
    });
}

// Sort Users Table
function sortUsersTable(field) {
    if (userSortField === field) {
        userSortAsc = !userSortAsc;
    } else {
        userSortField = field;
        userSortAsc = true;
    }

    // Update sort icons in headers
    const headers = ['name', 'user_id', 'phone_number', 'email', 'total_bookings', 'total_spend', 'status'];
    headers.forEach(h => {
        const icon = document.getElementById(`sort-icon-${h}`);
        if (icon) {
            if (h === field) {
                icon.innerHTML = userSortAsc ? '&#9652;' : '&#9662;'; // up/down arrows
                icon.style.color = 'var(--text-primary)';
            } else {
                icon.innerHTML = '&#9656;'; // default side arrow
                icon.style.color = 'var(--text-muted)';
            }
        }
    });

    // Sort the list
    loadedUsers.sort((a, b) => {
        let valA = a[field];
        let valB = b[field];

        if (field === 'total_bookings' || field === 'total_spend') {
            valA = Number(valA || 0);
            valB = Number(valB || 0);
        } else {
            // Handle string casing
            if (typeof valA === 'string') valA = valA.toLowerCase();
            if (typeof valB === 'string') valB = valB.toLowerCase();
            if (valA === null || valA === undefined) valA = '';
            if (valB === null || valB === undefined) valB = '';
        }

        // Compare
        if (valA < valB) return userSortAsc ? -1 : 1;
        if (valA > valB) return userSortAsc ? 1 : -1;
        return 0;
    });

    renderUsersTable(loadedUsers);
}

// Selection Handlers
function toggleSelectUser(userId, checked) {
    if (checked) {
        selectedUserIds.add(userId);
    } else {
        selectedUserIds.delete(userId);
    }
    
    // Sync Select All checkbox state
    const checkboxes = document.querySelectorAll('.user-checkbox');
    const checkedBoxes = document.querySelectorAll('.user-checkbox:checked');
    const selectAllBox = document.getElementById('selectAllUsers');
    if (selectAllBox) {
        selectAllBox.checked = checkboxes.length > 0 && checkboxes.length === checkedBoxes.length;
    }
}

function toggleSelectAllUsers(checked) {
    const checkboxes = document.querySelectorAll('.user-checkbox');
    checkboxes.forEach(cb => {
        cb.checked = checked;
        toggleSelectUser(cb.value, checked);
    });
}

// User Profile Slide Drawer
function openUserDrawer(user) {
    currentInspectedUser = user;
    const initials = user.name ? user.name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase() : 'U';
    
    let statusClass = 'success';
    if (user.status === 'Inactive') statusClass = 'neutral';
    if (user.status === 'Blocked') statusClass = 'danger';

    const joinDate = new Date(user.created_at).toLocaleDateString('en-IN', {
        day: '2-digit',
        month: 'short',
        year: 'numeric'
    });

    const isBlocked = user.status === 'Blocked';
    const actionButtonHtml = isBlocked 
        ? `<button class="btn-drawer-action btn-success" onclick="updateUserStatusFromDrawer('${user.user_id}', 'Active')">Reactivate Account</button>`
        : `<button class="btn-drawer-action btn-danger" onclick="updateUserStatusFromDrawer('${user.user_id}', 'Blocked')">Suspend Account</button>`;

    const drawerBody = document.getElementById('drawerBody');
    drawerBody.innerHTML = `
        <div class="drawer-user-header">
            <div class="drawer-avatar-large">${initials}</div>
            <h3 class="drawer-user-name">${user.name || 'Anonymous'}</h3>
            <span class="badge ${statusClass}">${user.status}</span>
        </div>
        
        <div class="drawer-section">
            <h4>Account Details</h4>
            <div class="drawer-detail-grid">
                <div class="detail-label">User ID</div>
                <div class="detail-value"><code>${user.user_id}</code></div>
                
                <div class="detail-label">Phone</div>
                <div class="detail-value">${user.phone_number}</div>
                
                <div class="detail-label">Email</div>
                <div class="detail-value">${user.email || '-'}</div>
                
                <div class="detail-label">Joined On</div>
                <div class="detail-value">${joinDate}</div>
            </div>
        </div>

        <div class="drawer-section">
            <h4>Activity Metrics</h4>
            <div class="drawer-detail-grid">
                <div class="detail-label">Total Bookings</div>
                <div class="detail-value"><strong>${user.total_bookings}</strong></div>
                
                <div class="detail-label">Total Spent</div>
                <div class="detail-value"><strong>₹${Number(user.total_spend).toFixed(2)}</strong></div>
            </div>
        </div>

        <div class="drawer-actions">
            ${actionButtonHtml}
        </div>
    `;

    document.getElementById('userDrawerBackdrop').classList.add('active');
    document.getElementById('userDetailDrawer').classList.add('active');
}

function closeUserDrawer() {
    document.getElementById('userDrawerBackdrop').classList.remove('active');
    document.getElementById('userDetailDrawer').classList.remove('active');
    currentInspectedUser = null;
}

// User status PATCH update
async function updateUserStatusFromDrawer(userId, newStatus) {
    const actionText = newStatus === 'Blocked' ? 'suspend' : 'reactivate';
    if (!confirm(`Are you sure you want to ${actionText} this user's account?`)) {
        return;
    }

    try {
        const updatedUser = await apiCall(`/api/admin/users/${userId}/status`, 'PATCH', { status: newStatus });
        alert(`User account has been successfully ${newStatus === 'Blocked' ? 'suspended' : 'activated'}.`);
        
        // Refresh the drawer content with updated info
        openUserDrawer(updatedUser);
        
        // Refresh the users list
        await loadUsersData();
    } catch (err) {
        console.error("Failed to update user status:", err);
    }
}

// Fetch all transactions and render in separate screen
async function loadTransactionsLedger() {
    try {
        const txns = await apiCall('/api/admin/transactions');
        const tbody = document.querySelector('#transactionsLedgerTable tbody');
        tbody.innerHTML = '';

        if (txns.length === 0) {
            tbody.innerHTML = `<tr><td colspan="9" class="text-center">No transactions registered yet</td></tr>`;
            return;
        }

        txns.forEach(t => {
            const date = new Date(t.created_at).toLocaleDateString('en-IN');
            let statusClass = 'neutral';
            if (t.txn_status === 'success') statusClass = 'success';
            if (t.txn_status === 'failed') statusClass = 'danger';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${t.txn_id.substring(0, 8)}</code></td>
                <td><code>${t.booking.eticket_code}</code></td>
                <td><code>${t.razorpay_order_id}</code></td>
                <td><code>${t.razorpay_payment_id || '-'}</code></td>
                <td><strong>${t.txn_type.toUpperCase()}</strong></td>
                <td><span class="badge ${statusClass}">${t.txn_status}</span></td>
                <td>₹${Number(t.amount).toFixed(2)}</td>
                <td>${date}</td>
                <td>
                    <div style="display: flex; gap: 5px;">
                        <button class="btn-action text-secondary" onclick="openTransactionEditModal('${t.txn_id}', '${t.booking_id}', '${escapeHtml(t.razorpay_order_id)}', '${escapeHtml(t.razorpay_payment_id || '')}', '${t.txn_type}', '${t.txn_status}', ${Number(t.amount)})">Edit</button>
                        <button class="btn-action text-danger" onclick="deleteTransaction('${t.txn_id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

// Fetch push broadcasts and render in delivery logs
async function loadBroadcastsData2() {
    try {
        const broadcasts = await apiCall('/api/admin/broadcasts');
        const tbody = document.querySelector('#broadcastsTable2 tbody');
        tbody.innerHTML = '';

        if (broadcasts.length === 0) {
            tbody.innerHTML = `<tr><td colspan="5" class="text-center">No broadcasts sent yet</td></tr>`;
            return;
        }

        broadcasts.forEach(b => {
            const date = new Date(b.sent_at).toLocaleString('en-IN');
            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${b.broadcast_id.substring(0, 8)}</code></td>
                <td><span class="badge neutral">${b.audience_type}</span></td>
                <td><strong>${b.title}</strong></td>
                <td><span class="badge success">${b.status}</span></td>
                <td>${date}</td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

// Escape HTML Helper
function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");
}

// Dynamic tab loading endpoints
async function loadTournamentsData() {
    try {
        const tournaments = await apiCall('/api/admin/tournaments');
        const tbody = document.querySelector('#tournamentsTable tbody');
        tbody.innerHTML = '';

        if (tournaments.length === 0) {
            tbody.innerHTML = `<tr><td colspan="8" class="text-center">No tournaments listed yet</td></tr>`;
            return;
        }

        tournaments.forEach(t => {
            let statusClass = 'neutral';
            if (t.status === 'open') statusClass = 'success';
            if (t.status === 'upcoming') statusClass = 'pending';
            if (t.status === 'completed') statusClass = 'neutral';
            if (t.status === 'cancelled') statusClass = 'danger';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${t.tournament_id.substring(0, 8)}</code></td>
                <td><strong>${t.name}</strong></td>
                <td>${t.venue.name}</td>
                <td><span class="badge neutral">${t.sport_type}</span></td>
                <td>₹${Number(t.registration_fee).toFixed(2)}</td>
                <td>${t.max_participants} participants</td>
                <td><span class="badge ${statusClass}">${t.status}</span></td>
                <td>
                    <div style="display: flex; gap: 5px;">
                        <button class="btn-action text-secondary" onclick="openTournamentEditModal('${t.tournament_id}', '${t.venue_id}', '${escapeHtml(t.name)}', '${escapeHtml(t.sport_type)}', ${Number(t.registration_fee)}, ${t.max_participants}, '${t.status}')">Edit</button>
                        <button class="btn-action text-danger" onclick="deleteTournament('${t.tournament_id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

async function loadReviewsData() {
    try {
        const reviews = await apiCall('/api/admin/reviews');
        const tbody = document.querySelector('#reviewsTable tbody');
        tbody.innerHTML = '';

        if (reviews.length === 0) {
            tbody.innerHTML = `<tr><td colspan="7" class="text-center">No reviews registered yet</td></tr>`;
            return;
        }

        reviews.forEach(r => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${r.review_id.substring(0, 8)}</code></td>
                <td><strong>${r.user.name || 'Anonymous'}</strong><br><small>${r.user.phone_number}</small></td>
                <td>${r.venue.name}</td>
                <td>★ ${Number(r.rating).toFixed(1)}</td>
                <td>${r.comment}</td>
                <td>${r.reply ? `<em>"${r.reply}"</em>` : '-'}</td>
                <td>
                    <div style="display: flex; gap: 5px;">
                        <button class="btn-action text-secondary" onclick="openReviewEditModal('${r.review_id}', '${r.venue_id}', '${r.user_id}', '${r.booking_id}', ${r.rating}, '${escapeHtml(r.comment)}', '${escapeHtml(r.reply || '')}')">Reply/Edit</button>
                        <button class="btn-action text-danger" onclick="deleteReview('${r.review_id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

async function loadSettlementsData() {
    try {
        const settlements = await apiCall('/api/admin/settlements');
        const tbody = document.querySelector('#settlementsTable tbody');
        tbody.innerHTML = '';

        if (settlements.length === 0) {
            tbody.innerHTML = `<tr><td colspan="9" class="text-center">No settlements calculated yet</td></tr>`;
            return;
        }

        settlements.forEach(s => {
            const start = new Date(s.period_start).toLocaleDateString('en-IN');
            const end = new Date(s.period_end).toLocaleDateString('en-IN');
            let statusClass = 'neutral';
            if (s.status === 'settled') statusClass = 'success';
            if (s.status === 'pending') statusClass = 'pending';
            if (s.status === 'failed') statusClass = 'danger';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${s.settlement_id.substring(0, 8)}</code></td>
                <td>${s.partner.phone_number}</td>
                <td>${start}</td>
                <td>${end}</td>
                <td>₹${Number(s.gross_amount).toFixed(2)}</td>
                <td>₹${Number(s.platform_fee).toFixed(2)}</td>
                <td>₹${Number(s.net_amount).toFixed(2)}</td>
                <td><span class="badge ${statusClass}">${s.status}</span></td>
                <td>
                    <div style="display: flex; gap: 5px;">
                        <button class="btn-action text-secondary" onclick="openSettlementEditModal('${s.settlement_id}', '${s.partner_id}', '${s.period_start.substring(0, 10)}', '${s.period_end.substring(0, 10)}', ${Number(s.gross_amount)}, ${Number(s.platform_fee)}, ${Number(s.net_amount)}, '${s.status}')">Edit</button>
                        <button class="btn-action text-danger" onclick="deleteSettlement('${s.settlement_id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

async function loadBannersData() {
    try {
        const banners = await apiCall('/api/admin/banners');
        const tbody = document.querySelector('#bannersTable tbody');
        tbody.innerHTML = '';

        if (banners.length === 0) {
            tbody.innerHTML = `<tr><td colspan="7" class="text-center">No hero banners configured yet</td></tr>`;
            return;
        }

        banners.forEach(b => {
            let badgeClass = b.is_active ? 'success' : 'danger';
            const row = document.createElement('tr');
            row.innerHTML = `
                <td><code>${b.banner_id.substring(0, 8)}</code></td>
                <td><strong>${b.title}</strong></td>
                <td><code>${b.image_url}</code></td>
                <td><span class="badge neutral">${b.target_app}</span></td>
                <td>${b.display_order}</td>
                <td><span class="badge ${badgeClass}">${b.is_active ? 'Active' : 'Inactive'}</span></td>
                <td>
                    <div style="display: flex; gap: 5px;">
                        <button class="btn-action text-secondary" onclick="openBannerEditModal('${b.banner_id}', '${escapeHtml(b.title)}', '${escapeHtml(b.image_url)}', '${escapeHtml(b.link_url || '')}', '${b.target_app}', ${b.display_order}, ${b.is_active})">Edit</button>
                        <button class="btn-action text-danger" onclick="deleteBanner('${b.banner_id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

async function loadAuditLogsData() {
    try {
        const logs = await apiCall('/api/admin/audit-logs');
        const tbody = document.querySelector('#auditLogsTable tbody');
        tbody.innerHTML = '';

        if (logs.length === 0) {
            tbody.innerHTML = `<tr><td colspan="5" class="text-center">No audit logs registered yet</td></tr>`;
            return;
        }

        logs.forEach(l => {
            const timeStr = new Date(l.time).toLocaleString('en-IN');
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${timeStr}</td>
                <td><code>${l.operator}</code></td>
                <td>${l.action}</td>
                <td><code>${l.resourceId.substring(0, 8)}</code></td>
                <td><span class="badge success">${l.result}</span></td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

async function clearAuditLogs() {
    if (!confirm("Are you sure you want to clear all system audit logs?")) return;
    try {
        await apiCall('/api/admin/audit-logs', 'DELETE');
        loadAuditLogsData();
        alert("Audit logs cleared.");
    } catch (err) {
        console.error(err);
    }
}

async function loadSettingsData() {
    try {
        const settings = await apiCall('/api/admin/settings');
        document.getElementById('settings-platformName').value = settings.platformName;
        document.getElementById('settings-supportEmail').value = settings.supportEmail;
        document.getElementById('settings-minWithdrawal').value = settings.minWithdrawal;
        document.getElementById('settings-convenienceFee').value = settings.convenienceFee;
    } catch (err) {
        console.error(err);
    }
}

async function saveSettings(e) {
    e.preventDefault();
    const platformName = document.getElementById('settings-platformName').value;
    const supportEmail = document.getElementById('settings-supportEmail').value;
    const minWithdrawal = Number(document.getElementById('settings-minWithdrawal').value);
    const convenienceFee = Number(document.getElementById('settings-convenienceFee').value);

    try {
        await apiCall('/api/admin/settings', 'POST', {
            platformName,
            supportEmail,
            minWithdrawal,
            convenienceFee
        });
        alert("Platform configurations updated successfully.");
        loadSettingsData();
    } catch (err) {
        console.error(err);
    }
}

async function loadRolesData() {
    try {
        const roles = await apiCall('/api/admin/roles');
        const tbody = document.querySelector('#rolesTable tbody');
        tbody.innerHTML = '';

        if (roles.length === 0) {
            tbody.innerHTML = `<tr><td colspan="5" class="text-center">No roles profiles created yet</td></tr>`;
            return;
        }

        roles.forEach(r => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td><strong>${r.roleName}</strong></td>
                <td>${r.description}</td>
                <td>${r.adminsCount}</td>
                <td><span class="badge neutral">${r.permissions}</span></td>
                <td>
                    <div style="display: flex; gap: 5px;">
                        <button class="btn-action text-secondary" onclick="openRoleEditModal('${r.id}', '${escapeHtml(r.roleName)}', '${escapeHtml(r.description)}', '${r.permissions}')">Edit</button>
                        <button class="btn-action text-danger" onclick="deleteRole('${r.id}')">Delete</button>
                    </div>
                </td>
            `;
            tbody.appendChild(row);
        });
    } catch (err) {
        console.error(err);
    }
}

// Dropdown dependency loaders
async function loadPartnersDropdown(selectId, selectedVal = '') {
    try {
        const partners = await apiCall('/api/admin/partners');
        const select = document.getElementById(selectId);
        select.innerHTML = '<option value="">Select a Partner (Host)...</option>';
        partners.forEach(p => {
            const option = document.createElement('option');
            option.value = p.partner_id;
            option.textContent = p.phone_number;
            if (p.partner_id === selectedVal) option.selected = true;
            select.appendChild(option);
        });
    } catch (err) {
        console.error(err);
    }
}

async function loadUsersDropdown(selectId, selectedVal = '') {
    try {
        const users = await apiCall('/api/admin/users');
        const select = document.getElementById(selectId);
        select.innerHTML = '<option value="">Select a User (Athlete)...</option>';
        users.forEach(u => {
            const option = document.createElement('option');
            option.value = u.user_id;
            option.textContent = `${u.name || 'Anonymous'} (${u.phone_number})`;
            if (u.user_id === selectedVal) option.selected = true;
            select.appendChild(option);
        });
    } catch (err) {
        console.error(err);
    }
}

async function loadVenuesDropdown(selectId, selectedVal = '') {
    try {
        const venues = await apiCall('/api/admin/venues');
        const select = document.getElementById(selectId);
        select.innerHTML = '<option value="">Select a Venue...</option>';
        venues.forEach(v => {
            const option = document.createElement('option');
            option.value = v.venue_id;
            option.textContent = v.name;
            if (v.venue_id === selectedVal) option.selected = true;
            select.appendChild(option);
        });
    } catch (err) {
        console.error(err);
    }
}

async function loadBookingsDropdown(selectId, selectedVal = '') {
    try {
        const bookings = await apiCall('/api/admin/bookings');
        const select = document.getElementById(selectId);
        select.innerHTML = '<option value="">Select a Booking Code...</option>';
        bookings.forEach(b => {
            const option = document.createElement('option');
            option.value = b.booking_id;
            option.textContent = `${b.eticket_code} (${b.venue.name})`;
            if (b.booking_id === selectedVal) option.selected = true;
            select.appendChild(option);
        });
    } catch (err) {
        console.error(err);
    }
}

async function loadBookingSlots(venueId, selectedVal = '') {
    const select = document.getElementById('booking-slot-id');
    if (!venueId) {
        select.innerHTML = '<option value="">Select a venue first...</option>';
        return;
    }
    try {
        const slots = await apiCall(`/api/admin/venues/${venueId}/slots`);
        select.innerHTML = '<option value="">Select a Slot...</option>';
        slots.forEach(s => {
            const option = document.createElement('option');
            option.value = s.slot_id;
            option.textContent = `${new Date(s.date).toLocaleDateString('en-IN')} @ ${s.start_time} - ${s.end_time} (${s.status})`;
            if (s.slot_id === selectedVal) option.selected = true;
            select.appendChild(option);
        });
    } catch (err) {
        console.error(err);
    }
}

// Modal opening / closing triggers
function openUserCreateModal() {
    document.getElementById('userModalTitle').textContent = "Create New User";
    document.getElementById('userForm').reset();
    document.getElementById('user-id').value = '';
    openModal('userFormModal');
}

function openUserEditModal(id, name, email, phone, status) {
    document.getElementById('userModalTitle').textContent = "Edit User Details";
    document.getElementById('user-id').value = id;
    document.getElementById('user-name').value = name;
    document.getElementById('user-email').value = email;
    document.getElementById('user-phone').value = phone;
    document.getElementById('user-status').value = status;
    openModal('userFormModal');
}

function openPartnerCreateModal() {
    document.getElementById('partnerModalTitle').textContent = "Create New Partner";
    document.getElementById('partnerForm').reset();
    document.getElementById('partner-id').value = '';
    openModal('partnerFormModal');
}

function openPartnerEditModal(id, phone, kyc, tier, earnings) {
    document.getElementById('partnerModalTitle').textContent = "Edit Partner Details";
    document.getElementById('partner-id').value = id;
    document.getElementById('partner-phone').value = phone;
    document.getElementById('partner-kyc').value = kyc;
    document.getElementById('partner-tier').value = tier;
    document.getElementById('partner-earnings').value = earnings;
    openModal('partnerFormModal');
}

async function openVenueCreateModal() {
    document.getElementById('venueModalTitle').textContent = "Create New Venue";
    document.getElementById('venueForm').reset();
    document.getElementById('venue-id').value = '';
    document.getElementById('venue-partner-group').classList.remove('hidden');
    await loadPartnersDropdown('venue-partner-id');
    openModal('venueFormModal');
}

async function openVenueEditModal(id, partnerId, name, sports, basePrice, status) {
    document.getElementById('venueModalTitle').textContent = "Edit Venue Details";
    document.getElementById('venue-id').value = id;
    document.getElementById('venue-partner-group').classList.add('hidden');
    document.getElementById('venue-name').value = name;
    document.getElementById('venue-sports').value = sports;
    document.getElementById('venue-base-price').value = basePrice;
    document.getElementById('venue-status').value = status;
    openModal('venueFormModal');
}

async function openBookingCreateModal() {
    document.getElementById('bookingModalTitle').textContent = "Create Manual Booking";
    document.getElementById('bookingForm').reset();
    document.getElementById('booking-id').value = '';
    document.getElementById('booking-user-group').classList.remove('hidden');
    document.getElementById('booking-venue-group').classList.remove('hidden');
    document.getElementById('booking-slot-group').classList.remove('hidden');
    await loadUsersDropdown('booking-user-id');
    await loadVenuesDropdown('booking-venue-id');
    openModal('bookingFormModal');
}

async function openBookingEditModal(id, userId, venueId, slotId, paymentMode, onlineAmount, venueAmount, status) {
    document.getElementById('bookingModalTitle').textContent = "Edit Booking Details";
    document.getElementById('booking-id').value = id;
    document.getElementById('booking-user-group').classList.add('hidden');
    document.getElementById('booking-venue-group').classList.add('hidden');
    document.getElementById('booking-slot-group').classList.add('hidden');
    document.getElementById('booking-payment-mode').value = paymentMode;
    document.getElementById('booking-online-amount').value = onlineAmount;
    document.getElementById('booking-venue-amount').value = venueAmount;
    document.getElementById('booking-status').value = status;
    openModal('bookingFormModal');
}

async function openTournamentCreateModal() {
    document.getElementById('tournamentModalTitle').textContent = "Create New Tournament";
    document.getElementById('tournamentForm').reset();
    document.getElementById('tournament-id').value = '';
    document.getElementById('tournament-venue-group').classList.remove('hidden');
    await loadVenuesDropdown('tournament-venue-id');
    openModal('tournamentFormModal');
}

async function openTournamentEditModal(id, venueId, name, sport, fee, maxParticipants, status) {
    document.getElementById('tournamentModalTitle').textContent = "Edit Tournament Details";
    document.getElementById('tournament-id').value = id;
    document.getElementById('tournament-venue-group').classList.add('hidden');
    document.getElementById('tournament-name').value = name;
    document.getElementById('tournament-sport').value = sport;
    document.getElementById('tournament-fee').value = fee;
    document.getElementById('tournament-max-participants').value = maxParticipants;
    document.getElementById('tournament-status').value = status;
    openModal('tournamentFormModal');
}

async function openReviewCreateModal() {
    document.getElementById('reviewModalTitle').textContent = "Create New Review";
    document.getElementById('reviewForm').reset();
    document.getElementById('review-id').value = '';
    document.getElementById('review-venue-group').classList.remove('hidden');
    document.getElementById('review-user-group').classList.remove('hidden');
    document.getElementById('review-booking-group').classList.remove('hidden');
    await loadVenuesDropdown('review-venue-id');
    await loadUsersDropdown('review-user-id');
    await loadBookingsDropdown('review-booking-id');
    openModal('reviewFormModal');
}

async function openReviewEditModal(id, venueId, userId, bookingId, rating, comment, reply) {
    document.getElementById('reviewModalTitle').textContent = "Edit Review Reply";
    document.getElementById('review-id').value = id;
    document.getElementById('review-venue-group').classList.add('hidden');
    document.getElementById('review-user-group').classList.add('hidden');
    document.getElementById('review-booking-group').classList.add('hidden');
    document.getElementById('review-rating').value = rating;
    document.getElementById('review-comment').value = comment;
    document.getElementById('review-reply').value = reply;
    openModal('reviewFormModal');
}

async function openSettlementCreateModal() {
    document.getElementById('settlementModalTitle').textContent = "Create Manual Settlement";
    document.getElementById('settlementForm').reset();
    document.getElementById('settlement-id').value = '';
    document.getElementById('settlement-partner-group').classList.remove('hidden');
    await loadPartnersDropdown('settlement-partner-id');
    openModal('settlementFormModal');
}

async function openSettlementEditModal(id, partnerId, start, end, gross, fee, net, status) {
    document.getElementById('settlementModalTitle').textContent = "Edit Settlement Details";
    document.getElementById('settlement-id').value = id;
    document.getElementById('settlement-partner-group').classList.add('hidden');
    document.getElementById('settlement-start').value = start;
    document.getElementById('settlement-end').value = end;
    document.getElementById('settlement-gross').value = gross;
    document.getElementById('settlement-fee').value = fee;
    document.getElementById('settlement-net').value = net;
    document.getElementById('settlement-status').value = status;
    openModal('settlementFormModal');
}

async function openTransactionCreateModal() {
    document.getElementById('transactionModalTitle').textContent = "Create Transaction Entry";
    document.getElementById('transactionForm').reset();
    document.getElementById('transaction-id').value = '';
    document.getElementById('transaction-booking-group').classList.remove('hidden');
    await loadBookingsDropdown('transaction-booking-id');
    openModal('transactionFormModal');
}

async function openTransactionEditModal(id, bookingId, orderId, paymentId, type, status, amount) {
    document.getElementById('transactionModalTitle').textContent = "Edit Transaction Details";
    document.getElementById('transaction-id').value = id;
    document.getElementById('transaction-booking-group').classList.add('hidden');
    document.getElementById('transaction-order-id').value = orderId;
    document.getElementById('transaction-payment-id').value = paymentId;
    document.getElementById('transaction-type').value = type;
    document.getElementById('transaction-status').value = status;
    document.getElementById('transaction-amount').value = amount;
    openModal('transactionFormModal');
}

function openBannerCreateModal() {
    document.getElementById('bannerModalTitle').textContent = "Create Banner Placement";
    document.getElementById('bannerForm').reset();
    document.getElementById('banner-id').value = '';
    openModal('bannerFormModal');
}

function openBannerEditModal(id, title, imageUrl, linkUrl, targetApp, displayOrder, isActive) {
    document.getElementById('bannerModalTitle').textContent = "Edit Banner Details";
    document.getElementById('banner-id').value = id;
    document.getElementById('banner-title').value = title;
    document.getElementById('banner-image-url').value = imageUrl;
    document.getElementById('banner-link-url').value = linkUrl;
    document.getElementById('banner-target-app').value = targetApp;
    document.getElementById('banner-order').value = displayOrder;
    document.getElementById('banner-active').value = String(isActive);
    openModal('bannerFormModal');
}

async function openDisputeCreateModal() {
    document.getElementById('disputeModalTitle').textContent = "File Manual Dispute";
    document.getElementById('disputeForm').reset();
    document.getElementById('dispute-id').value = '';
    document.getElementById('dispute-booking-group').classList.remove('hidden');
    await loadBookingsDropdown('dispute-booking-id');
    openModal('disputeFormModal');
}

function openDisputeEditModal(id, bookingId, raisedBy, details, status) {
    document.getElementById('disputeModalTitle').textContent = "Edit Dispute Case";
    document.getElementById('dispute-id').value = id;
    document.getElementById('dispute-booking-group').classList.add('hidden');
    document.getElementById('dispute-raised-by').value = raisedBy;
    document.getElementById('dispute-details').value = details;
    document.getElementById('dispute-status').value = status;
    openModal('disputeFormModal');
}

function openRoleCreateModal() {
    document.getElementById('roleModalTitle').textContent = "Create Role Profile";
    document.getElementById('roleForm').reset();
    document.getElementById('role-id').value = '';
    openModal('roleFormModal');
}

function openRoleEditModal(id, name, description, permissions) {
    document.getElementById('roleModalTitle').textContent = "Edit Role Profile";
    document.getElementById('role-id').value = id;
    document.getElementById('role-name').value = name;
    document.getElementById('role-description').value = description;
    document.getElementById('role-permissions').value = permissions;
    openModal('roleFormModal');
}

// Form Submission methods
async function submitUser(e) {
    e.preventDefault();
    const id = document.getElementById('user-id').value;
    const name = document.getElementById('user-name').value;
    const email = document.getElementById('user-email').value;
    const phone_number = document.getElementById('user-phone').value;
    const status = document.getElementById('user-status').value;

    const payload = { name, email, phone_number, status };
    try {
        if (id) {
            await apiCall(`/api/admin/users/${id}`, 'PATCH', payload);
        } else {
            await apiCall('/api/admin/users', 'POST', payload);
        }
        closeModal('userFormModal');
        loadUsersData();
    } catch (err) {
        console.error(err);
    }
}

async function submitPartner(e) {
    e.preventDefault();
    const id = document.getElementById('partner-id').value;
    const phone_number = document.getElementById('partner-phone').value;
    const kyc_status = document.getElementById('partner-kyc').value;
    const plan_tier = document.getElementById('partner-tier').value;
    const total_earnings = Number(document.getElementById('partner-earnings').value);

    const payload = { phone_number, kyc_status, plan_tier, total_earnings };
    try {
        if (id) {
            await apiCall(`/api/admin/partners/${id}`, 'PATCH', payload);
        } else {
            await apiCall('/api/admin/partners', 'POST', payload);
        }
        closeModal('partnerFormModal');
        loadPartnersData();
    } catch (err) {
        console.error(err);
    }
}

async function submitVenue(e) {
    e.preventDefault();
    const id = document.getElementById('venue-id').value;
    const partner_id = document.getElementById('venue-partner-id').value;
    const name = document.getElementById('venue-name').value;
    const sport_types = document.getElementById('venue-sports').value.split(',').map(s => s.trim()).filter(Boolean);
    const base_price = Number(document.getElementById('venue-base-price').value);
    const status = document.getElementById('venue-status').value;

    const payload = { partner_id, name, sport_types, base_price, status };
    try {
        if (id) {
            await apiCall(`/api/admin/venues/${id}`, 'PATCH', { name, sport_types, base_price, status });
        } else {
            await apiCall('/api/admin/venues', 'POST', payload);
        }
        closeModal('venueFormModal');
        loadVenuesData();
    } catch (err) {
        console.error(err);
    }
}

async function submitBooking(e) {
    e.preventDefault();
    const id = document.getElementById('booking-id').value;
    const user_id = document.getElementById('booking-user-id').value;
    const venue_id = document.getElementById('booking-venue-id').value;
    const slot_id = document.getElementById('booking-slot-id').value;
    const payment_mode = document.getElementById('booking-payment-mode').value;
    const online_amount = Number(document.getElementById('booking-online-amount').value);
    const venue_amount = Number(document.getElementById('booking-venue-amount').value);
    const status = document.getElementById('booking-status').value;

    const convenience_fee = 60;
    const commission_amount = (online_amount + venue_amount) * 0.03;
    const gst_amount = commission_amount * 0.18;
    const partner_amount = (online_amount + venue_amount) - commission_amount - gst_amount;

    const payload = {
        user_id, venue_id, slot_id, payment_mode,
        convenience_fee, commission_amount, gst_amount, partner_amount,
        online_amount, venue_amount, status
    };

    try {
        if (id) {
            await apiCall(`/api/admin/bookings/${id}`, 'PATCH', { payment_mode, online_amount, venue_amount, status });
        } else {
            await apiCall('/api/admin/bookings', 'POST', payload);
        }
        closeModal('bookingFormModal');
        loadBookingsData();
    } catch (err) {
        console.error(err);
    }
}

async function submitTournament(e) {
    e.preventDefault();
    const id = document.getElementById('tournament-id').value;
    const venue_id = document.getElementById('tournament-venue-id').value;
    const name = document.getElementById('tournament-name').value;
    const sport_type = document.getElementById('tournament-sport').value;
    const registration_fee = Number(document.getElementById('tournament-fee').value);
    const max_participants = Number(document.getElementById('tournament-max-participants').value);
    const status = document.getElementById('tournament-status').value;

    const payload = { venue_id, name, sport_type, registration_fee, max_participants, status };
    try {
        if (id) {
            await apiCall(`/api/admin/tournaments/${id}`, 'PATCH', { name, sport_type, registration_fee, max_participants, status });
        } else {
            await apiCall('/api/admin/tournaments', 'POST', payload);
        }
        closeModal('tournamentFormModal');
        loadTournamentsData();
    } catch (err) {
        console.error(err);
    }
}

async function submitReview(e) {
    e.preventDefault();
    const id = document.getElementById('review-id').value;
    const venue_id = document.getElementById('review-venue-id').value;
    const user_id = document.getElementById('review-user-id').value;
    const booking_id = document.getElementById('review-booking-id').value;
    const rating = Number(document.getElementById('review-rating').value);
    const comment = document.getElementById('review-comment').value;
    const reply = document.getElementById('review-reply').value;

    const payload = { venue_id, user_id, booking_id, rating, comment, reply };
    try {
        if (id) {
            await apiCall(`/api/admin/reviews/${id}`, 'PATCH', { rating, comment, reply });
        } else {
            await apiCall('/api/admin/reviews', 'POST', payload);
        }
        closeModal('reviewFormModal');
        loadReviewsData();
    } catch (err) {
        console.error(err);
    }
}

async function submitSettlement(e) {
    e.preventDefault();
    const id = document.getElementById('settlement-id').value;
    const partner_id = document.getElementById('settlement-partner-id').value;
    const period_start = document.getElementById('settlement-start').value;
    const period_end = document.getElementById('settlement-end').value;
    const gross_amount = Number(document.getElementById('settlement-gross').value);
    const platform_fee = Number(document.getElementById('settlement-fee').value);
    const net_amount = Number(document.getElementById('settlement-net').value);
    const status = document.getElementById('settlement-status').value;

    const payload = { partner_id, period_start, period_end, gross_amount, platform_fee, net_amount, status };
    try {
        if (id) {
            await apiCall(`/api/admin/settlements/${id}`, 'PATCH', payload);
        } else {
            await apiCall('/api/admin/settlements', 'POST', payload);
        }
        closeModal('settlementFormModal');
        loadSettlementsData();
    } catch (err) {
        console.error(err);
    }
}

async function submitTransaction(e) {
    e.preventDefault();
    const id = document.getElementById('transaction-id').value;
    const booking_id = document.getElementById('transaction-booking-id').value;
    const razorpay_order_id = document.getElementById('transaction-order-id').value;
    const razorpay_payment_id = document.getElementById('transaction-payment-id').value;
    const txn_type = document.getElementById('transaction-type').value;
    const txn_status = document.getElementById('transaction-status').value;
    const amount = Number(document.getElementById('transaction-amount').value);

    const payload = { booking_id, razorpay_order_id, razorpay_payment_id, txn_type, txn_status, amount };
    try {
        if (id) {
            await apiCall(`/api/admin/transactions/${id}`, 'PATCH', { razorpay_order_id, razorpay_payment_id, txn_type, txn_status, amount });
        } else {
            await apiCall('/api/admin/transactions', 'POST', payload);
        }
        closeModal('transactionFormModal');
        loadTransactionsLedger();
    } catch (err) {
        console.error(err);
    }
}

async function submitBanner(e) {
    e.preventDefault();
    const id = document.getElementById('banner-id').value;
    const title = document.getElementById('banner-title').value;
    const image_url = document.getElementById('banner-image-url').value;
    const link_url = document.getElementById('banner-link-url').value;
    const target_app = document.getElementById('banner-target-app').value;
    const display_order = Number(document.getElementById('banner-order').value);
    const is_active = document.getElementById('banner-active').value === "true";

    const payload = { title, image_url, link_url, target_app, display_order, is_active };
    try {
        if (id) {
            await apiCall(`/api/admin/banners/${id}`, 'PATCH', payload);
        } else {
            await apiCall('/api/admin/banners', 'POST', payload);
        }
        closeModal('bannerFormModal');
        loadBannersData();
    } catch (err) {
        console.error(err);
    }
}

async function submitDispute(e) {
    e.preventDefault();
    const id = document.getElementById('dispute-id').value;
    const booking_id = document.getElementById('dispute-booking-id').value;
    const raised_by = document.getElementById('dispute-raised-by').value;
    const details = document.getElementById('dispute-details').value;
    const status = document.getElementById('dispute-status').value;

    const payload = { booking_id, raised_by, details, status };
    try {
        if (id) {
            await apiCall(`/api/admin/disputes/${id}/resolve`, 'PATCH', { resolution: 'closed_no_action' });
        } else {
            await apiCall('/api/admin/disputes', 'POST', payload);
        }
        closeModal('disputeFormModal');
        loadDisputesData();
    } catch (err) {
        console.error(err);
    }
}

async function submitRole(e) {
    e.preventDefault();
    const id = document.getElementById('role-id').value;
    const roleName = document.getElementById('role-name').value;
    const description = document.getElementById('role-description').value;
    const permissions = document.getElementById('role-permissions').value;

    const payload = { roleName, description, permissions };
    try {
        if (id) {
            await apiCall(`/api/admin/roles/${id}`, 'PATCH', payload);
        } else {
            await apiCall('/api/admin/roles', 'POST', payload);
        }
        closeModal('roleFormModal');
        loadRolesData();
    } catch (err) {
        console.error(err);
    }
}

// Delete functions
async function deleteUser(id) {
    if (!confirm("Are you sure you want to delete this user? This will also delete all of their bookings and reviews.")) return;
    try {
        await apiCall(`/api/admin/users/${id}`, 'DELETE');
        loadUsersData();
    } catch (err) {
        console.error(err);
    }
}

async function deletePartner(id) {
    if (!confirm("Are you sure you want to delete this partner host? All listed venues will be removed.")) return;
    try {
        await apiCall(`/api/admin/partners/${id}`, 'DELETE');
        loadPartnersData();
    } catch (err) {
        console.error(err);
    }
}

async function deleteVenue(id) {
    if (!confirm("Are you sure you want to delete this venue? All slots and related bookings will be deleted.")) return;
    try {
        await apiCall(`/api/admin/venues/${id}`, 'DELETE');
        loadVenuesData();
    } catch (err) {
        console.error(err);
    }
}

async function deleteBooking(id) {
    if (!confirm("Are you sure you want to delete this booking?")) return;
    try {
        await apiCall(`/api/admin/bookings/${id}`, 'DELETE');
        loadBookingsData();
    } catch (err) {
        console.error(err);
    }
}

async function deleteTournament(id) {
    if (!confirm("Are you sure you want to delete this tournament league?")) return;
    try {
        await apiCall(`/api/admin/tournaments/${id}`, 'DELETE');
        loadTournamentsData();
    } catch (err) {
        console.error(err);
    }
}

async function deleteReview(id) {
    if (!confirm("Are you sure you want to delete this review?")) return;
    try {
        await apiCall(`/api/admin/reviews/${id}`, 'DELETE');
        loadReviewsData();
    } catch (err) {
        console.error(err);
    }
}

async function deleteSettlement(id) {
    if (!confirm("Are you sure you want to delete this settlement invoice?")) return;
    try {
        await apiCall(`/api/admin/settlements/${id}`, 'DELETE');
        loadSettlementsData();
    } catch (err) {
        console.error(err);
    }
}

async function deleteTransaction(id) {
    if (!confirm("Are you sure you want to delete this transaction ledger entry?")) return;
    try {
        await apiCall(`/api/admin/transactions/${id}`, 'DELETE');
        loadTransactionsLedger();
    } catch (err) {
        console.error(err);
    }
}

async function deleteBanner(id) {
    if (!confirm("Are you sure you want to delete this banner placement?")) return;
    try {
        await apiCall(`/api/admin/banners/${id}`, 'DELETE');
        loadBannersData();
    } catch (err) {
        console.error(err);
    }
}

async function deleteDispute(id) {
    if (!confirm("Are you sure you want to delete this dispute case?")) return;
    try {
        await apiCall(`/api/admin/disputes/${id}`, 'DELETE');
        loadDisputesData();
    } catch (err) {
        console.error(err);
    }
}

async function deleteRole(id) {
    if (!confirm("Are you sure you want to delete this role profile?")) return;
    try {
        await apiCall(`/api/admin/roles/${id}`, 'DELETE');
        loadRolesData();
    } catch (err) {
        console.error(err);
    }
}

// NEW LOADER FUNCTIONS & ACTION HANDLERS

async function loadMilestonesData() {
    try {
        const milestoneList = [
            { id: 'first_booking', name: 'First Booking Complete', count: 1, type: 'Welcome', rewardType: 'Free Slot' },
            { id: 'bookings_5', name: '5 Bookings Milestone', count: 5, type: 'Loyalty', rewardType: 'Cashback' },
            { id: 'bookings_10', name: '10 Bookings Milestone', count: 10, type: 'Power User', rewardType: 'Coupon' },
            { id: 'bookings_50', name: '50 Bookings Milestone', count: 50, type: 'Elite Athlete', rewardType: 'Coupon' }
        ];

        const tbody = document.querySelector('#milestonesTable tbody');
        if (tbody) {
            tbody.innerHTML = '';
            milestoneList.forEach(m => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td><strong>${m.name}</strong></td>
                    <td>${m.count} bookings</td>
                    <td><span class="badge active">${m.type}</span></td>
                    <td>${m.rewardType}</td>
                    <td>
                        <button class="btn-action text-accent" onclick="alert('Configuring milestone: ${m.name}')">Configure</button>
                    </td>
                `;
                tbody.appendChild(row);
            });
        }
    } catch (err) {
        console.error(err);
    }
}

async function loadRewardsData() {
    try {
        const tbody = document.querySelector('#rewardsTable tbody');
        if (tbody) {
            tbody.innerHTML = `
                <tr>
                    <td><strong>Free Slot Reward</strong></td>
                    <td>Applies free booking slot coupon to next booking</td>
                    <td><span class="badge success">Active</span></td>
                    <td>
                        <button class="btn-action text-accent" onclick="alert('Configuring Free Slot Reward')">Configure</button>
                    </td>
                </tr>
                <tr>
                    <td><strong>Loyalty Points Award</strong></td>
                    <td>Earn 10 points per ₹100 spend on online bookings</td>
                    <td><span class="badge success">Active</span></td>
                    <td>
                        <button class="btn-action text-accent" onclick="alert('Configuring Loyalty Points Award')">Configure</button>
                    </td>
                </tr>
                <tr>
                    <td><strong>Cashback Award</strong></td>
                    <td>10% cashback up to ₹100 inside user wallet</td>
                    <td><span class="badge neutral">Inactive</span></td>
                    <td>
                        <button class="btn-action text-accent" onclick="alert('Configuring Cashback Award')">Configure</button>
                    </td>
                </tr>
            `;
        }
    } catch (err) {
        console.error(err);
    }
}

async function loadKycData() {
    try {
        const documents = await apiCall('/api/admin/kyc/pending');
        const tbody = document.querySelector('#kycTable tbody');
        if (tbody) {
            tbody.innerHTML = '';
            if (documents.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" class="text-center">No pending KYC verifications</td></tr>';
                return;
            }
            documents.forEach(doc => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td><strong>${doc.partner_id.substring(0,8)}...</strong></td>
                    <td><span class="badge active">${doc.document_type}</span></td>
                    <td><a href="${doc.file_url}" target="_blank" style="color: var(--accent-primary); text-decoration: underline;">View Document</a></td>
                    <td><span class="badge warning">${doc.status}</span></td>
                    <td>
                        <div style="display: flex; gap: 5px;">
                            <button class="btn-action text-success" onclick="approveKyc('${doc.doc_id}')">Approve</button>
                            <button class="btn-action text-danger" onclick="rejectKyc('${doc.doc_id}')">Reject</button>
                        </div>
                    </td>
                `;
                tbody.appendChild(row);
            });
        }
    } catch (err) {
        console.error(err);
    }
}

async function approveKyc(docId) {
    try {
        await apiCall(`/api/admin/kyc/document/${docId}`, 'PATCH', { status: 'verified' });
        alert("KYC document approved successfully!");
        loadKycData();
    } catch (err) {
        console.error(err);
    }
}

async function rejectKyc(docId) {
    const note = prompt("Enter rejection reason:");
    if (note === null) return;
    try {
        await apiCall(`/api/admin/kyc/document/${docId}`, 'PATCH', { status: 'rejected', rejection_note: note });
        alert("KYC document rejected.");
        loadKycData();
    } catch (err) {
        console.error(err);
    }
}

async function loadApprovalsData() {
    try {
        const venues = await apiCall('/api/admin/venues');
        const pendingVenues = venues.filter(v => v.status === 'unlisted');
        const tbody = document.querySelector('#venueApprovalsTable tbody');
        if (tbody) {
            tbody.innerHTML = '';
            if (pendingVenues.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" class="text-center">No venues awaiting approval</td></tr>';
                return;
            }
            pendingVenues.forEach(v => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td><strong>${v.name}</strong></td>
                    <td>${v.sport_types.join(', ')}</td>
                    <td>₹${Number(v.base_price).toFixed(2)}</td>
                    <td><span class="badge warning">Pending Approval</span></td>
                    <td>
                        <div style="display: flex; gap: 5px;">
                            <button class="btn-action text-success" onclick="updateVenueApproval('${v.venue_id}', 'listed')">Approve & List</button>
                            <button class="btn-action text-danger" onclick="updateVenueApproval('${v.venue_id}', 'unlisted')">Reject</button>
                        </div>
                    </td>
                `;
                tbody.appendChild(row);
            });
        }
    } catch (err) {
        console.error(err);
    }
}

async function updateVenueApproval(venueId, status) {
    try {
        await apiCall(`/api/admin/venues/${venueId}/status`, 'PATCH', { status });
        alert(`Venue status updated to ${status}`);
        loadApprovalsData();
    } catch (err) {
        console.error(err);
    }
}

async function loadFeaturedVenuesData() {
    try {
        const venues = await apiCall('/api/admin/venues');
        const tbody = document.querySelector('#featuredVenuesTable tbody');
        if (tbody) {
            tbody.innerHTML = '';
            venues.forEach(v => {
                const isFeatured = v.status === 'listed'; 
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td><strong>${v.name}</strong></td>
                    <td>${v.sport_types.join(', ')}</td>
                    <td>★ ${Number(v.avg_rating).toFixed(1)}</td>
                    <td><span class="badge ${isFeatured ? 'success' : 'neutral'}">${isFeatured ? 'Featured' : 'Standard'}</span></td>
                    <td>
                        <button class="btn-action text-accent" onclick="toggleVenueFeaturedStatus('${v.venue_id}')">Toggle Feature</button>
                    </td>
                `;
                tbody.appendChild(row);
            });
        }
    } catch (err) {
        console.error(err);
    }
}

async function toggleVenueFeaturedStatus(venueId) {
    try {
        await apiCall(`/api/admin/venues/${venueId}/feature`, 'PATCH');
        alert("Venue featured state toggled!");
        loadFeaturedVenuesData();
    } catch (err) {
        console.error(err);
    }
}

async function loadRefundsData() {
    try {
        const txns = await apiCall('/api/admin/transactions');
        const refunds = txns.filter(t => t.txn_type === 'refund');
        const tbody = document.querySelector('#refundsTable tbody');
        if (tbody) {
            tbody.innerHTML = '';
            if (refunds.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" class="text-center">No refund transactions recorded</td></tr>';
                return;
            }
            refunds.forEach(r => {
                const row = document.createElement('tr');
                row.innerHTML = `
                    <td><strong>${r.txn_id.substring(0,8)}...</strong></td>
                    <td>${r.booking_id.substring(0,8)}...</td>
                    <td>₹${Number(r.amount).toFixed(2)}</td>
                    <td><span class="badge ${r.txn_status === 'SUCCESS' ? 'success' : 'warning'}">${r.txn_status}</span></td>
                    <td>${new Date(r.created_at).toLocaleString()}</td>
                `;
                tbody.appendChild(row);
            });
        }
    } catch (err) {
        console.error(err);
    }
}

async function loadReassignmentData() {
    try {
        const bookings = await apiCall('/api/admin/bookings');
        const select = document.getElementById('reassignBookingSelect');
        if (select) {
            select.innerHTML = '<option value="">Select a Booking to Reassign...</option>';
            bookings.forEach(b => {
                const option = document.createElement('option');
                option.value = b.booking_id;
                option.textContent = `${b.eticket_code} - ${b.venue.name} (${new Date(b.created_at).toLocaleDateString()})`;
                select.appendChild(option);
            });
        }
    } catch (err) {
        console.error(err);
    }
}

async function loadCommissionsData() {
    try {
        const settings = await apiCall('/api/admin/settings');
        if (settings) {
            document.getElementById('commGlobalPct').value = settings.global_commission || 3.0;
            document.getElementById('commGstPct').value = settings.gst_percentage || 18.0;
            document.getElementById('commConvenienceFee').value = settings.convenience_fee || 10.0;
        }
    } catch (err) {
        console.error(err);
    }
}

async function saveCommissionSettings() {
    const global_commission = parseFloat(document.getElementById('commGlobalPct').value);
    const gst_percentage = parseFloat(document.getElementById('commGstPct').value);
    const convenience_fee = parseFloat(document.getElementById('commConvenienceFee').value);

    try {
        await apiCall('/api/admin/settings', 'POST', {
            global_commission,
            gst_percentage,
            convenience_fee
        });
        alert("Commission settings updated successfully!");
        loadCommissionsData();
    } catch (err) {
        console.error(err);
    }
}

async function loadRegistrationsData() {
    try {
        const tbody = document.querySelector('#registrationsTable tbody');
        if (tbody) {
            tbody.innerHTML = `
                <tr>
                    <td><strong>REG-0012</strong></td>
                    <td>Summer Slam Tennis</td>
                    <td>Net Busters FC</td>
                    <td>₹500.00</td>
                    <td><span class="badge success">Paid</span></td>
                </tr>
                <tr>
                    <td><strong>REG-0013</strong></td>
                    <td>Summer Slam Tennis</td>
                    <td>Court Masters</td>
                    <td>₹500.00</td>
                    <td><span class="badge success">Paid</span></td>
                </tr>
                <tr>
                    <td><strong>REG-0014</strong></td>
                    <td>Cricket Championship</td>
                    <td>Eleven Stars</td>
                    <td>₹1000.00</td>
                    <td><span class="badge warning">Pending</span></td>
                </tr>
            `;
        }
    } catch (err) {
        console.error(err);
    }
}

async function loadChatMonitoringData() {
    try {
        const tbody = document.querySelector('#chatMonitoringTable tbody');
        if (tbody) {
            tbody.innerHTML = `
                <tr>
                    <td>User (John) ↔ Partner (Decathlon)</td>
                    <td>"Is the court open at 6 AM?"</td>
                    <td><span class="badge success">Clean</span></td>
                    <td>2026-06-18 10:15</td>
                    <td>
                        <button class="btn-action text-accent" onclick="alert('Viewing chat channel details')">Audit</button>
                    </td>
                </tr>
                <tr>
                    <td>User (Sania) ↔ Partner (SportsArena)</td>
                    <td>"Refund my money now or I will sue"</td>
                    <td><span class="badge warning">Escalated</span></td>
                    <td>2026-06-18 11:22</td>
                    <td>
                        <button class="btn-action text-accent" onclick="alert('Viewing chat channel details')">Audit</button>
                    </td>
                </tr>
                <tr>
                    <td>User (Rahul) ↔ Partner (Noida Complex)</td>
                    <td>"Call me on 9988776655 for direct discount"</td>
                    <td><span class="badge danger">Flagged (Spam)</span></td>
                    <td>2026-06-18 12:40</td>
                    <td>
                        <button class="btn-action text-danger" onclick="alert('User blocked from chat compliance')">Block</button>
                    </td>
                </tr>
            `;
        }
    } catch (err) {
        console.error(err);
    }
}

function loadReportsData() {
    console.log("Reports tab loaded");
}

function loadExportsData() {
    console.log("Exports tab loaded");
}
