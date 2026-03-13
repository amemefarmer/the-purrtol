/* ==============================================
   THE PURRTOL — Main JavaScript
   Vanilla JS. No frameworks. No build step.

   Handles:
   - Smooth scroll with fixed-nav offset
   - Mobile hamburger menu
   - Active nav link tracking (IntersectionObserver)
   - Nav background solidification on scroll
   - Back-to-top button visibility
   - Scroll reveal animations (sections + staggered children)
   ============================================== */

;(function () {
  'use strict';

  // Cache DOM references
  var nav       = document.getElementById('main-nav');
  var navToggle = document.querySelector('.nav__toggle');
  var navLinks  = document.querySelector('.nav__links');
  var allNavLinks = document.querySelectorAll('.nav__link');
  var backToTop = document.querySelector('.back-to-top');
  var sections  = document.querySelectorAll('.section[id]');


  /* ------------------------------------------
     SMOOTH SCROLL
     ------------------------------------------ */
  function initSmoothScroll() {
    document.addEventListener('click', function (e) {
      var anchor = e.target.closest('a[href^="#"]');
      if (!anchor) return;

      var targetId = anchor.getAttribute('href');
      if (targetId === '#' || targetId === '#hero') {
        e.preventDefault();
        closeMobileNav();
        window.scrollTo({ top: 0, behavior: 'smooth' });
        history.pushState(null, null, targetId);
        return;
      }

      var target = document.querySelector(targetId);
      if (!target) return;

      e.preventDefault();
      closeMobileNav();

      var navHeight = nav ? nav.offsetHeight : 0;
      var targetPos = target.getBoundingClientRect().top + window.scrollY - navHeight;

      window.scrollTo({ top: targetPos, behavior: 'smooth' });
      history.pushState(null, null, targetId);
    });
  }


  /* ------------------------------------------
     MOBILE NAV
     ------------------------------------------ */
  function initMobileNav() {
    if (!navToggle) return;

    navToggle.addEventListener('click', function () {
      var isOpen = this.getAttribute('aria-expanded') === 'true';
      this.setAttribute('aria-expanded', String(!isOpen));
      navLinks.classList.toggle('is-open');
      document.body.style.overflow = isOpen ? '' : 'hidden';
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') closeMobileNav();
    });
  }

  function closeMobileNav() {
    if (!navToggle) return;
    navToggle.setAttribute('aria-expanded', 'false');
    navLinks.classList.remove('is-open');
    document.body.style.overflow = '';
  }


  /* ------------------------------------------
     ACTIVE NAV TRACKING
     ------------------------------------------ */
  function initActiveNav() {
    if (!sections.length) return;

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var id = entry.target.getAttribute('id');
        allNavLinks.forEach(function (link) {
          link.classList.toggle('is-active', link.getAttribute('href') === '#' + id);
        });
      });
    }, {
      rootMargin: '-35% 0px -65% 0px'
    });

    sections.forEach(function (s) { observer.observe(s); });
  }


  /* ------------------------------------------
     NAV SCROLL EFFECT
     ------------------------------------------ */
  function initNavScroll() {
    if (!nav) return;
    var threshold = 80;

    function update() {
      nav.classList.toggle('is-scrolled', window.scrollY > threshold);
    }

    window.addEventListener('scroll', update, { passive: true });
    update();
  }


  /* ------------------------------------------
     BACK TO TOP
     ------------------------------------------ */
  function initBackToTop() {
    if (!backToTop) return;

    function update() {
      backToTop.classList.toggle('is-visible', window.scrollY > window.innerHeight * 0.8);
    }

    window.addEventListener('scroll', update, { passive: true });
    update();
  }


  /* ------------------------------------------
     SCROLL REVEAL
     Adds .reveal to sections (except hero).
     Adds .reveal-stagger to grid containers.
     Uses IntersectionObserver to trigger.
     ------------------------------------------ */
  function initScrollReveal() {
    // Check reduced motion preference
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

    // Mark sections for reveal
    document.querySelectorAll('.section:not(.hero)').forEach(function (el) {
      el.classList.add('reveal');
    });

    // Mark grids for stagger
    document.querySelectorAll(
      '.card-grid, .stats-grid, .waste-grid, .lessons-grid, .timeline'
    ).forEach(function (el) {
      el.classList.add('reveal-stagger');
    });

    // Observe all reveal targets
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, {
      threshold: 0.08,
      rootMargin: '0px 0px -40px 0px'
    });

    document.querySelectorAll('.reveal, .reveal-stagger').forEach(function (el) {
      observer.observe(el);
    });
  }


  /* ------------------------------------------
     INIT
     ------------------------------------------ */
  function init() {
    initSmoothScroll();
    initMobileNav();
    initActiveNav();
    initNavScroll();
    initBackToTop();
    initScrollReveal();

    // Console easter egg
    console.log(
      '%c\uD83D\uDC31 The PurrTol %c\u2014 built with Claude, abandoned by Claude.',
      'color: #00bbff; font-size: 14px; font-weight: bold;',
      'color: #666; font-size: 12px;'
    );
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
