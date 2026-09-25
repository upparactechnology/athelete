/**
 * Athlete's POV (APOV) - Coming Soon Website Logic
 */

document.addEventListener('DOMContentLoaded', () => {
  // 1. Scroll Reveal Animations with IntersectionObserver
  const revealElements = document.querySelectorAll('.reveal, .reveal-scale');

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
          observer.unobserve(entry.target);
        }
      });
    }, observerOptions);

    revealElements.forEach(el => revealObserver.observe(el));
  } else {
    revealElements.forEach(el => el.classList.add('reveal-active'));
  }

  // 2. Early Access Form Submission Handler
  const form = document.getElementById('early-access-form');
  const feedback = document.getElementById('form-feedback');

  if (form && feedback) {
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const emailInput = document.getElementById('subscriber-email');
      const email = emailInput ? emailInput.value.trim() : '';

      if (email) {
        // Save to local storage for demonstration/mocking purposes
        let subscribers = [];
        try {
          subscribers = JSON.parse(localStorage.getItem('apov_subscribers') || '[]');
        } catch (err) {
          subscribers = [];
        }
        
        if (!subscribers.includes(email)) {
          subscribers.push(email);
          localStorage.setItem('apov_subscribers', JSON.stringify(subscribers));
        }

        // Show success message
        feedback.textContent = 'Thank you! You have been added to our early access list.';
        feedback.className = 'form-feedback-message success';
        
        if (emailInput) {
          emailInput.value = '';
        }
      }
    });
  }
});
