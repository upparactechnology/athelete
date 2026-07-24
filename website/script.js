/**
 * Athlete's POV (APOV) - Website Interactive Logic
 * Mobile-First, Scroll Reveal Animations, App Switcher, Live Slot Simulator,
 * Partner Revenue Calculator, FAQs, & Smooth Navigation.
 */

document.addEventListener('DOMContentLoaded', () => {
  // 1. Scroll Reveal Animations with IntersectionObserver
  const revealElements = document.querySelectorAll('.reveal, .reveal-left, .reveal-right, .reveal-scale');

  if ('IntersectionObserver' in window) {
    const observerOptions = {
      root: null,
      threshold: 0.12,
      rootMargin: '0px 0px -40px 0px'
    };

    const revealObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('reveal-active');
          // Optionally unobserve after revealing once
          observer.unobserve(entry.target);
        }
      });
    }, observerOptions);

    revealElements.forEach(el => revealObserver.observe(el));
  } else {
    // Fallback if IntersectionObserver isn't supported
    revealElements.forEach(el => el.classList.add('reveal-active'));
  }

  // 2. Header Sticky & Mobile Drawer Menu Toggle
  const header = document.querySelector('header');
  const mobileToggle = document.querySelector('.mobile-toggle');
  const navMenu = document.querySelector('.nav-menu');

  window.addEventListener('scroll', () => {
    if (window.scrollY > 20) {
      header.classList.add('scrolled');
    } else {
      header.classList.remove('scrolled');
    }
  });

  if (mobileToggle && navMenu) {
    mobileToggle.addEventListener('click', (e) => {
      e.stopPropagation();
      navMenu.classList.toggle('active');
      mobileToggle.classList.toggle('active');
    });

    document.addEventListener('click', (e) => {
      if (!navMenu.contains(e.target) && !mobileToggle.contains(e.target)) {
        navMenu.classList.remove('active');
        mobileToggle.classList.remove('active');
      }
    });
  }

  // Close nav on click
  document.querySelectorAll('.nav-link').forEach(link => {
    link.addEventListener('click', () => {
      if (navMenu) navMenu.classList.remove('active');
      if (mobileToggle) mobileToggle.classList.remove('active');
    });
  });

  // 3. Dual App Switcher (Player App vs Partner App)
  const tabPlayerBtn = document.getElementById('tab-player-btn');
  const tabPartnerBtn = document.getElementById('tab-partner-btn');
  const tabPlayerContent = document.getElementById('tab-player-content');
  const tabPartnerContent = document.getElementById('tab-partner-content');

  if (tabPlayerBtn && tabPartnerBtn) {
    tabPlayerBtn.addEventListener('click', () => {
      tabPlayerBtn.className = 'tab-btn active-player';
      tabPartnerBtn.className = 'tab-btn';
      tabPlayerContent.classList.add('active');
      tabPartnerContent.classList.remove('active');
    });

    tabPartnerBtn.addEventListener('click', () => {
      tabPartnerBtn.className = 'tab-btn active-partner';
      tabPlayerBtn.className = 'tab-btn';
      tabPartnerContent.classList.add('active');
      tabPlayerContent.classList.remove('active');
    });
  }

  // 4. Interactive Live Booking Simulator Engine
  const sportChips = document.querySelectorAll('.sport-chip');
  const slotItems = document.querySelectorAll('.slot-item.status-available');
  const selectedCountEl = document.getElementById('sim-selected-count');
  const totalAmountEl = document.getElementById('sim-total-amount');
  const onlineDepositEl = document.getElementById('sim-online-deposit');
  const cashVenueEl = document.getElementById('sim-cash-venue');

  let activeSport = 'Box Cricket';
  let slotBasePrice = 1200;

  const sportPrices = {
    'Box Cricket': 1200,
    'Football': 1600,
    'Badminton': 400,
    'Tennis': 800,
    'Pickleball': 600,
    'Basketball': 1000,
    'Volleyball': 900,
    'Table Tennis': 300,
    'Skate Park': 500,
    'E-Sports Hub': 400,
    'Rock Climbing': 700,
    'Ultimate Frisbee': 600
  };

  sportChips.forEach(chip => {
    chip.addEventListener('click', () => {
      sportChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      activeSport = chip.getAttribute('data-sport') || chip.innerText.trim();
      slotBasePrice = sportPrices[activeSport] || 1000;
      updateSimulatorPrices();
      updateBookingTotals();
    });
  });

  function updateSimulatorPrices() {
    document.querySelectorAll('.slot-item').forEach((item, index) => {
      const priceSpan = item.querySelector('.price');
      if (priceSpan) {
        const isPeak = index >= 5;
        const slotPrice = isPeak ? Math.round(slotBasePrice * 1.2) : slotBasePrice;
        priceSpan.innerText = `₹${slotPrice}`;
        item.setAttribute('data-price', slotPrice);
      }
    });
  }

  slotItems.forEach(item => {
    item.addEventListener('click', () => {
      item.classList.toggle('status-selected');
      updateBookingTotals();
    });
  });

  function updateBookingTotals() {
    const selectedElements = document.querySelectorAll('.slot-item.status-selected');
    const selectedCount = selectedElements.length;

    let total = 0;
    selectedElements.forEach(el => {
      total += parseInt(el.getAttribute('data-price') || slotBasePrice);
    });

    const convenienceFee = Math.round(total * 0.04);
    const grandTotal = total + (selectedCount > 0 ? convenienceFee : 0);

    const onlineDeposit = Math.round(grandTotal * 0.30);
    const cashAtVenue = grandTotal - onlineDeposit;

    if (selectedCountEl) selectedCountEl.innerText = `${selectedCount} Slot${selectedCount !== 1 ? 's' : ''}`;
    if (totalAmountEl) totalAmountEl.innerText = `₹${grandTotal.toLocaleString()}`;
    if (onlineDepositEl) onlineDepositEl.innerText = `₹${onlineDeposit.toLocaleString()}`;
    if (cashVenueEl) cashVenueEl.innerText = `₹${cashAtVenue.toLocaleString()}`;

    const ticketSport = document.getElementById('ticket-sport-name');
    const ticketAmount = document.getElementById('ticket-amount-paid');

    if (ticketSport) ticketSport.innerText = `${activeSport} Booking`;
    if (ticketAmount) ticketAmount.innerText = `₹${onlineDeposit.toLocaleString()} (Deposit Paid)`;
  }

  updateSimulatorPrices();
  updateBookingTotals();

  // 5. Partner Revenue Calculator
  const courtsSlider = document.getElementById('calc-courts');
  const hoursSlider = document.getElementById('calc-hours');
  const rateSlider = document.getElementById('calc-rate');

  const courtsVal = document.getElementById('calc-courts-val');
  const hoursVal = document.getElementById('calc-hours-val');
  const rateVal = document.getElementById('calc-rate-val');

  const grossMonthlyEl = document.getElementById('calc-gross-monthly');
  const commDeductEl = document.getElementById('calc-comm-deduct');
  const netPayoutEl = document.getElementById('calc-net-payout');

  function calculateEarnings() {
    if (!courtsSlider || !hoursSlider || !rateSlider) return;

    const courts = parseInt(courtsSlider.value);
    const hours = parseInt(hoursSlider.value);
    const rate = parseInt(rateSlider.value);

    if (courtsVal) courtsVal.innerText = courts;
    if (hoursVal) hoursVal.innerText = `${hours} hrs/day`;
    if (rateVal) rateVal.innerText = `₹${rate}/hr`;

    const dailyRevenue = courts * hours * rate;
    const grossMonthly = dailyRevenue * 30;

    const commission = grossMonthly * 0.03;
    const gstOnCommission = commission * 0.18;
    const totalFees = Math.round(commission + gstOnCommission);
    const netPayout = grossMonthly - totalFees;

    if (grossMonthlyEl) grossMonthlyEl.innerText = `₹${grossMonthly.toLocaleString()}`;
    if (commDeductEl) commDeductEl.innerText = `-₹${totalFees.toLocaleString()} (3% + GST)`;
    if (netPayoutEl) netPayoutEl.innerText = `₹${netPayout.toLocaleString()}`;

    // 3D Payout Box Animation Pop
    const payoutBox = document.querySelector('.3d-depth-payout');
    if (payoutBox) {
      payoutBox.style.transform = 'translateZ(65px) scale(1.04)';
      setTimeout(() => {
        payoutBox.style.transform = '';
      }, 180);
    }
  }

  if (courtsSlider && hoursSlider && rateSlider) {
    courtsSlider.addEventListener('input', calculateEarnings);
    hoursSlider.addEventListener('input', calculateEarnings);
    rateSlider.addEventListener('input', calculateEarnings);
    calculateEarnings();
  }

  // 6. FAQ Accordion Logic
  const faqItems = document.querySelectorAll('.faq-item');

  faqItems.forEach(item => {
    const questionBtn = item.querySelector('.faq-question');
    if (questionBtn) {
      questionBtn.addEventListener('click', () => {
        const isActive = item.classList.contains('active');
        faqItems.forEach(other => other.classList.remove('active'));
        if (!isActive) {
          item.classList.add('active');
        }
      });
    }
  });

  // 7. Active Scroll Spy
  const sections = document.querySelectorAll('section[id]');
  window.addEventListener('scroll', () => {
    const scrollY = window.pageYOffset;

    sections.forEach(current => {
      const sectionHeight = current.offsetHeight;
      const sectionTop = current.offsetTop - 120;
      const sectionId = current.getAttribute('id');
      const navLink = document.querySelector(`.nav-menu a[href*=${sectionId}]`);

      if (navLink) {
        if (scrollY > sectionTop && scrollY <= sectionTop + sectionHeight) {
          document.querySelectorAll('.nav-link').forEach(n => n.classList.remove('active'));
          navLink.classList.add('active');
        }
      }
    });
  });

  // 8. Scroll Progress Indicator
  const scrollProgressBar = document.getElementById('scrollProgress');
  window.addEventListener('scroll', () => {
    const winScroll = document.body.scrollTop || document.documentElement.scrollTop;
    const height = document.documentElement.scrollHeight - document.documentElement.clientHeight;
    const scrolled = (winScroll / height) * 100;
    if (scrollProgressBar) {
      scrollProgressBar.style.width = scrolled + "%";
    }
  });

  // 9. Custom 3D Mouse Glow & Tilt Effect on Cards
  const interactiveCards = document.querySelectorAll('.feature-card, .sport-card, .result-box, .sim-box, .ticket-preview-box, .app-preview-card');
  interactiveCards.forEach(card => {
    card.addEventListener('mousemove', e => {
      const rect = card.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      
      card.style.setProperty('--mouse-x', `${x}px`);
      card.style.setProperty('--mouse-y', `${y}px`);
      
      const width = rect.width;
      const height = rect.height;
      const centerX = width / 2;
      const centerY = height / 2;
      
      const rotateY = ((x - centerX) / centerX) * 8;
      const rotateX = ((centerY - y) / centerY) * 8;
      
      card.style.transform = `perspective(1000px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale3d(1.02, 1.02, 1.02)`;
      card.style.transition = 'transform 0.1s ease-out, box-shadow 0.3s ease';
    });
    
    card.style.transformStyle = 'preserve-3d';
    
    card.addEventListener('mouseleave', () => {
      card.style.transform = `perspective(1000px) rotateX(0deg) rotateY(0deg) scale3d(1, 1, 1)`;
      card.style.transition = 'transform 0.4s cubic-bezier(0.16, 1, 0.3, 1), box-shadow 0.3s ease';
    });
  });

  // 10. Animated Numerical Counters on Scroll
  const counters = document.querySelectorAll('.counter-target');
  if (counters.length > 0 && 'IntersectionObserver' in window) {
    const counterObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          const el = entry.target;
          const target = parseFloat(el.getAttribute('data-target') || '0');
          const suffix = el.getAttribute('data-suffix') || '';
          const decimals = parseInt(el.getAttribute('data-decimals') || '0');
          const duration = 1800;
          const startTime = performance.now();

          function updateCounter(now) {
            const elapsed = now - startTime;
            const progress = Math.min(elapsed / duration, 1);
            const easeProgress = 1 - (1 - progress) * (1 - progress);
            const current = target * easeProgress;

            el.innerText = (decimals > 0 ? current.toFixed(decimals) : Math.floor(current).toLocaleString()) + suffix;

            if (progress < 1) {
              requestAnimationFrame(updateCounter);
            }
          }

          requestAnimationFrame(updateCounter);
          observer.unobserve(el);
        }
      });
    }, { threshold: 0.3 });

    counters.forEach(counter => counterObserver.observe(counter));
  }
});
