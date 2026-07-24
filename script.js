document.addEventListener('DOMContentLoaded', () => {
    // 1. Sticky Header Effect
    const header = document.querySelector('header');
    const handleScroll = () => {
        if (window.scrollY > 50) {
            header.classList.add('scrolled');
        } else {
            header.classList.remove('scrolled');
        }
    };
    window.addEventListener('scroll', handleScroll);
    handleScroll(); // Initial check

    // 2. Mobile Menu Toggle
    const mobileToggle = document.querySelector('.mobile-toggle');
    const navMenu = document.querySelector('.nav-menu');
    const navLinks = document.querySelectorAll('.nav-link');

    mobileToggle.addEventListener('click', () => {
        mobileToggle.classList.toggle('open');
        navMenu.classList.toggle('open');
    });

    navLinks.forEach(link => {
        link.addEventListener('click', () => {
            mobileToggle.classList.remove('open');
            navMenu.classList.remove('open');
        });
    });

    // 3. Scroll Reveal Animation using Intersection Observer
    const revealElements = document.querySelectorAll('.reveal');
    const revealObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('active');
                observer.unobserve(entry.target); // Trigger only once
            }
        });
    }, {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    });

    revealElements.forEach(element => {
        revealObserver.observe(element);
    });

    // 4. Active Link Highlighting on Scroll
    const sections = document.querySelectorAll('section');
    window.addEventListener('scroll', () => {
        let currentSectionId = '';
        sections.forEach(section => {
            const sectionTop = section.offsetTop - 120;
            if (window.scrollY >= sectionTop) {
                currentSectionId = section.getAttribute('id');
            }
        });

        navLinks.forEach(link => {
            link.classList.remove('active');
            if (link.getAttribute('href') === `#${currentSectionId}`) {
                link.classList.add('active');
            }
        });
    });

    // 5. Telemetry Dashboard Interactive Controller
    const dashboardData = {
        cycling: {
            title: "Downhill Road Cycling POV",
            desc: "Immersive wearable overlays syncing speed, elevation, heart rate, and real-time mapping for pro riders.",
            bg: "https://images.unsplash.com/photo-1541614101331-1a5a3a194e92?auto=format&fit=crop&w=1000&q=80",
            speed: "58.4",
            speedUnit: "km/h",
            hr: "168",
            stats: [
                { label: "Duration", value: "01:24:18", barWidth: "75%" },
                { label: "Distance", value: "48.2 km", barWidth: "85%" },
                { label: "Max Speed", value: "76.4 km/h", barWidth: "90%" },
                { label: "Avg Power", value: "285 Watts", barWidth: "65%" }
            ]
        },
        running: {
            title: "Trail Run Performance POV",
            desc: "Track stride frequency, heart rate zones, elevation profile, and vertical oscillation dynamically.",
            bg: "https://images.unsplash.com/photo-1502680390469-be75c86b636f?auto=format&fit=crop&w=1000&q=80",
            speed: "14.8",
            speedUnit: "km/h",
            hr: "155",
            stats: [
                { label: "Duration", value: "00:46:12", barWidth: "40%" },
                { label: "Distance", value: "10.4 km", barWidth: "50%" },
                { label: "Cadence", value: "178 spm", barWidth: "80%" },
                { label: "Elevation Gain", value: "320 m", barWidth: "45%" }
            ]
        },
        athletics: {
            title: "Olympic Sprinter Block POV",
            desc: "Analyze block exit force, acceleration vectors, and velocity optimization directly from the athlete's gaze.",
            bg: "https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?auto=format&fit=crop&w=1000&q=80",
            speed: "38.2",
            speedUnit: "km/h",
            hr: "182",
            stats: [
                { label: "Duration", value: "00:00:10", barWidth: "5%" },
                { label: "Distance", value: "100 m", barWidth: "10%" },
                { label: "Reaction Time", value: "0.142s", barWidth: "95%" },
                { label: "Max Velocity", value: "41.6 km/h", barWidth: "98%" }
            ]
        },
        fitness: {
            title: "High-Intensity CrossFit POV",
            desc: "Monitor power output, heart rate recovery rates, and calorie burn acceleration during intense circuits.",
            bg: "https://images.unsplash.com/photo-1517838277536-f5f99be501cd?auto=format&fit=crop&w=1000&q=80",
            speed: "N/A",
            speedUnit: "activity",
            hr: "174",
            stats: [
                { label: "Duration", value: "00:32:05", barWidth: "60%" },
                { label: "Active Energy", value: "480 kcal", barWidth: "70%" },
                { label: "Avg HR", value: "158 bpm", barWidth: "75%" },
                { label: "Sets Done", value: "6 / 8 Rounds", barWidth: "75%" }
            ]
        }
    };

    const tabButtons = document.querySelectorAll('.tab-btn');
    const dbBgImg = document.querySelector('.dashboard-bg-img');
    const hudSpeedVal = document.querySelector('.hud-speedometer .speed-val');
    const hudSpeedUnit = document.querySelector('.hud-speedometer .speed-unit');
    const hudHrVal = document.querySelector('.hud-heartrate .hr-val');
    const statsTitle = document.querySelector('.stats-sport-title');
    const statsDesc = document.querySelector('.stats-sport-desc');
    const statBoxes = document.querySelectorAll('.stats-grid .stat-box');
    const playBtn = document.querySelector('.play-overlay-btn');

    // Function to animate numbers
    const animateNumber = (element, targetValue) => {
        const target = parseFloat(targetValue);
        if (isNaN(target)) {
            element.textContent = targetValue;
            return;
        }

        const duration = 800; // ms
        const startTime = performance.now();
        const startValue = parseFloat(element.textContent) || 0;

        const updateNumber = (currentTime) => {
            const elapsedTime = currentTime - startTime;
            if (elapsedTime >= duration) {
                element.textContent = targetValue; // Ensure exact final value
            } else {
                const progress = elapsedTime / duration;
                // Cubic ease-out
                const easeOut = 1 - Math.pow(1 - progress, 3);
                const currentValue = startValue + (target - startValue) * easeOut;
                element.textContent = target % 1 === 0 ? Math.floor(currentValue) : currentValue.toFixed(1);
                requestAnimationFrame(updateNumber);
            }
        };
        requestAnimationFrame(updateNumber);
    };

    // Tab switching handler
    tabButtons.forEach(button => {
        button.addEventListener('click', () => {
            const category = button.getAttribute('data-category');
            if (!dashboardData[category]) return;

            // Update active tab button style
            tabButtons.forEach(btn => btn.classList.remove('active'));
            button.classList.add('active');

            const data = dashboardData[category];

            // Update Image & Text
            dbBgImg.style.opacity = '0';
            setTimeout(() => {
                dbBgImg.src = data.bg;
                dbBgImg.style.opacity = '1';
            }, 300);

            // Update HUD Overlays with animation
            animateNumber(hudSpeedVal, data.speed);
            hudSpeedUnit.textContent = data.speedUnit;
            animateNumber(hudHrVal, data.hr);

            // Update stats panel titles
            statsTitle.textContent = data.title;
            statsDesc.textContent = data.desc;

            // Update Stat Grid items
            data.stats.forEach((stat, index) => {
                if (statBoxes[index]) {
                    const labelEl = statBoxes[index].querySelector('.stat-lbl');
                    const numEl = statBoxes[index].querySelector('.stat-num');
                    const barEl = statBoxes[index].querySelector('.stat-bar');

                    labelEl.textContent = stat.label;
                    numEl.textContent = stat.value;
                    barEl.style.width = '0%'; // Reset bar
                    setTimeout(() => {
                        barEl.style.width = stat.barWidth; // Animate bar to new width
                    }, 50);
                }
            });
        });
    });

    // 6. Play Simulation Button
    let liveSimulationInterval = null;
    let timerSeconds = 0;
    const hudTimer = document.querySelector('.hud-timer');
    const hudBadge = document.querySelector('.hud-badge');

    const updateTimerText = () => {
        const hrs = Math.floor(timerSeconds / 3600).toString().padStart(2, '0');
        const mins = Math.floor((timerSeconds % 3600) / 60).toString().padStart(2, '0');
        const secs = (timerSeconds % 60).toString().padStart(2, '0');
        hudTimer.textContent = `${hrs}:${mins}:${secs}`;
    };

    const startSimulation = () => {
        playBtn.innerHTML = '&#10074;&#10074;'; // Pause icon
        playBtn.style.background = 'linear-gradient(135deg, #ef4444 0%, #b91c1c 100%)';
        hudBadge.style.display = 'flex';
        
        liveSimulationInterval = setInterval(() => {
            // Increment timer
            timerSeconds++;
            updateTimerText();

            // Slightly fluctuate heart rate & speed for realism
            const activeTab = document.querySelector('.tab-btn.active').getAttribute('data-category');
            const data = dashboardData[activeTab];
            
            if (data.speed !== "N/A") {
                const currentSpeed = parseFloat(hudSpeedVal.textContent);
                const deltaSpeed = (Math.random() - 0.5) * 2; // Fluctuates -1 to +1
                const nextSpeed = Math.max(0, currentSpeed + deltaSpeed);
                hudSpeedVal.textContent = nextSpeed.toFixed(1);
            }

            const currentHr = parseInt(hudHrVal.textContent);
            const deltaHr = Math.floor((Math.random() - 0.5) * 4); // Fluctuates -2 to +2
            const nextHr = Math.min(195, Math.max(90, currentHr + deltaHr));
            hudHrVal.textContent = nextHr;
        }, 1000);
    };

    const stopSimulation = () => {
        playBtn.innerHTML = '&#9654;'; // Play icon
        playBtn.style.background = 'var(--gradient-accent)';
        hudBadge.style.display = 'none';
        
        if (liveSimulationInterval) {
            clearInterval(liveSimulationInterval);
            liveSimulationInterval = null;
        }
    };

    playBtn.addEventListener('click', () => {
        if (liveSimulationInterval) {
            stopSimulation();
        } else {
            startSimulation();
        }
    });

    // Initialize first category stats display on load
    const initTelemetry = () => {
        const defaultCategory = 'cycling';
        const data = dashboardData[defaultCategory];
        data.stats.forEach((stat, index) => {
            if (statBoxes[index]) {
                const barEl = statBoxes[index].querySelector('.stat-bar');
                barEl.style.width = stat.barWidth;
            }
        });
    };
    initTelemetry();

    // 7. Contact Form Handling & Validation
    const contactForm = document.getElementById('contactForm');
    const formStatus = document.getElementById('formStatus');

    if (contactForm) {
        contactForm.addEventListener('submit', (e) => {
            e.preventDefault();
            
            const name = document.getElementById('name').value.trim();
            const email = document.getElementById('email').value.trim();
            const sport = document.getElementById('sport').value;
            const message = document.getElementById('message').value.trim();

            // Clear previous statuses
            formStatus.className = 'form-status';
            formStatus.style.display = 'none';

            // Simple validation
            if (!name || !email || !message) {
                formStatus.textContent = 'Please fill out all required fields.';
                formStatus.classList.add('error');
                return;
            }

            if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
                formStatus.textContent = 'Please enter a valid email address.';
                formStatus.classList.add('error');
                return;
            }

            // Mock successful submission
            const submitBtn = contactForm.querySelector('.submit-btn');
            const originalText = submitBtn.textContent;
            
            submitBtn.disabled = true;
            submitBtn.textContent = 'Sending...';

            setTimeout(() => {
                submitBtn.disabled = false;
                submitBtn.textContent = originalText;
                
                formStatus.textContent = `Thanks, ${name}! Your inquiry for Athlete's POV ${sport} training program has been successfully received. We will get back to you within 24 hours.`;
                formStatus.classList.add('success');
                
                // Clear form inputs
                contactForm.reset();
            }, 1200);
        });
    }

    // 8. Custom 3D Mouse Glow Effect on Cards
    const cards = document.querySelectorAll('.feature-card');
    cards.forEach(card => {
        card.addEventListener('mousemove', e => {
            const rect = card.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;
            card.style.setProperty('--mouse-x', `${x}px`);
            card.style.setProperty('--mouse-y', `${y}px`);
        });
    });
});
