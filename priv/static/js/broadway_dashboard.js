/**
 * BroadwayDashboard - Pan and Zoom functionality for pipeline graphs
 *
 * This module provides LiveView hooks for adding pan/zoom capabilities
 * to the Broadway pipeline visualization.
 *
 * Usage:
 *   1. Include this script in your application
 *   2. Register the hooks with your LiveSocket
 *   3. Or use the BroadwayDashboard.Hooks module with on_mount
 */

(function() {
  "use strict";

  // Default configuration
  const DEFAULT_CONFIG = {
    minScale: 0.1,
    maxScale: 5,
    scaleStep: 0.1,
    wheelZoomSpeed: 0.001
  };

  /**
   * Creates a pan/zoom controller for an SVG element
   */
  class PanZoomController {
    constructor(container, svg, config = {}) {
      this.container = container;
      this.svg = svg;
      this.config = { ...DEFAULT_CONFIG, ...config };

      // Transform state
      this.scale = 1;
      this.translateX = 0;
      this.translateY = 0;

      // Drag state
      this.isDragging = false;
      this.lastMouseX = 0;
      this.lastMouseY = 0;

      // Store original viewBox for reset
      this.originalViewBox = svg.getAttribute('viewBox');
      this.originalStyle = svg.getAttribute('style') || '';

      // Create transform group wrapper
      this.setupTransformGroup();

      // Bind event handlers
      this.bindEvents();
    }

    setupTransformGroup() {
      // Check if we already have a transform group
      let transformGroup = this.svg.querySelector('[data-panzoom-group]');

      if (!transformGroup) {
        // Create a new group to wrap all SVG content
        transformGroup = document.createElementNS('http://www.w3.org/2000/svg', 'g');
        transformGroup.setAttribute('data-panzoom-group', 'true');

        // Move all children into the group
        while (this.svg.firstChild) {
          transformGroup.appendChild(this.svg.firstChild);
        }

        this.svg.appendChild(transformGroup);
      }

      this.transformGroup = transformGroup;
      this.updateTransform();
    }

    bindEvents() {
      // Mouse wheel for zoom
      this.container.addEventListener('wheel', this.handleWheel.bind(this), { passive: false });

      // Mouse drag for pan
      this.container.addEventListener('mousedown', this.handleMouseDown.bind(this));
      document.addEventListener('mousemove', this.handleMouseMove.bind(this));
      document.addEventListener('mouseup', this.handleMouseUp.bind(this));

      // Touch events for mobile
      this.container.addEventListener('touchstart', this.handleTouchStart.bind(this), { passive: false });
      this.container.addEventListener('touchmove', this.handleTouchMove.bind(this), { passive: false });
      this.container.addEventListener('touchend', this.handleTouchEnd.bind(this));

      // Prevent context menu on right-click drag
      this.container.addEventListener('contextmenu', (e) => {
        if (this.isDragging) e.preventDefault();
      });
    }

    handleWheel(e) {
      e.preventDefault();

      const rect = this.container.getBoundingClientRect();
      const mouseX = e.clientX - rect.left;
      const mouseY = e.clientY - rect.top;

      // Calculate zoom
      const delta = -e.deltaY * this.config.wheelZoomSpeed;
      const newScale = Math.max(
        this.config.minScale,
        Math.min(this.config.maxScale, this.scale * (1 + delta))
      );

      if (newScale !== this.scale) {
        // Zoom towards mouse position
        const scaleRatio = newScale / this.scale;
        this.translateX = mouseX - (mouseX - this.translateX) * scaleRatio;
        this.translateY = mouseY - (mouseY - this.translateY) * scaleRatio;
        this.scale = newScale;

        this.updateTransform();
        this.updateZoomIndicator();
      }
    }

    handleMouseDown(e) {
      if (e.button === 0) { // Left mouse button
        this.isDragging = true;
        this.lastMouseX = e.clientX;
        this.lastMouseY = e.clientY;
        this.container.style.cursor = 'grabbing';
        e.preventDefault();
      }
    }

    handleMouseMove(e) {
      if (this.isDragging) {
        const dx = e.clientX - this.lastMouseX;
        const dy = e.clientY - this.lastMouseY;

        this.translateX += dx;
        this.translateY += dy;

        this.lastMouseX = e.clientX;
        this.lastMouseY = e.clientY;

        this.updateTransform();
      }
    }

    handleMouseUp() {
      if (this.isDragging) {
        this.isDragging = false;
        this.container.style.cursor = 'grab';
      }
    }

    // Touch event handling
    handleTouchStart(e) {
      if (e.touches.length === 1) {
        this.isDragging = true;
        this.lastMouseX = e.touches[0].clientX;
        this.lastMouseY = e.touches[0].clientY;
        e.preventDefault();
      } else if (e.touches.length === 2) {
        this.isPinching = true;
        this.lastPinchDistance = this.getPinchDistance(e.touches);
        this.lastPinchCenter = this.getPinchCenter(e.touches);
        e.preventDefault();
      }
    }

    handleTouchMove(e) {
      if (this.isDragging && e.touches.length === 1) {
        const dx = e.touches[0].clientX - this.lastMouseX;
        const dy = e.touches[0].clientY - this.lastMouseY;

        this.translateX += dx;
        this.translateY += dy;

        this.lastMouseX = e.touches[0].clientX;
        this.lastMouseY = e.touches[0].clientY;

        this.updateTransform();
        e.preventDefault();
      } else if (this.isPinching && e.touches.length === 2) {
        const newDistance = this.getPinchDistance(e.touches);
        const newCenter = this.getPinchCenter(e.touches);

        const scaleChange = newDistance / this.lastPinchDistance;
        const newScale = Math.max(
          this.config.minScale,
          Math.min(this.config.maxScale, this.scale * scaleChange)
        );

        if (newScale !== this.scale) {
          const rect = this.container.getBoundingClientRect();
          const centerX = newCenter.x - rect.left;
          const centerY = newCenter.y - rect.top;

          const scaleRatio = newScale / this.scale;
          this.translateX = centerX - (centerX - this.translateX) * scaleRatio;
          this.translateY = centerY - (centerY - this.translateY) * scaleRatio;
          this.scale = newScale;

          this.updateTransform();
          this.updateZoomIndicator();
        }

        this.lastPinchDistance = newDistance;
        this.lastPinchCenter = newCenter;
        e.preventDefault();
      }
    }

    handleTouchEnd(e) {
      if (e.touches.length === 0) {
        this.isDragging = false;
        this.isPinching = false;
      } else if (e.touches.length === 1) {
        this.isPinching = false;
        this.isDragging = true;
        this.lastMouseX = e.touches[0].clientX;
        this.lastMouseY = e.touches[0].clientY;
      }
    }

    getPinchDistance(touches) {
      const dx = touches[0].clientX - touches[1].clientX;
      const dy = touches[0].clientY - touches[1].clientY;
      return Math.sqrt(dx * dx + dy * dy);
    }

    getPinchCenter(touches) {
      return {
        x: (touches[0].clientX + touches[1].clientX) / 2,
        y: (touches[0].clientY + touches[1].clientY) / 2
      };
    }

    updateTransform() {
      const transform = `translate(${this.translateX}px, ${this.translateY}px) scale(${this.scale})`;
      this.svg.style.transform = transform;
      this.svg.style.transformOrigin = '0 0';
    }

    updateZoomIndicator() {
      const indicator = this.container.querySelector('[data-zoom-level]');
      if (indicator) {
        indicator.textContent = `${Math.round(this.scale * 100)}%`;
      }
    }

    // Public methods for control buttons
    zoomIn() {
      const rect = this.container.getBoundingClientRect();
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;

      const newScale = Math.min(this.config.maxScale, this.scale * (1 + this.config.scaleStep));
      const scaleRatio = newScale / this.scale;

      this.translateX = centerX - (centerX - this.translateX) * scaleRatio;
      this.translateY = centerY - (centerY - this.translateY) * scaleRatio;
      this.scale = newScale;

      this.updateTransform();
      this.updateZoomIndicator();
    }

    zoomOut() {
      const rect = this.container.getBoundingClientRect();
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;

      const newScale = Math.max(this.config.minScale, this.scale * (1 - this.config.scaleStep));
      const scaleRatio = newScale / this.scale;

      this.translateX = centerX - (centerX - this.translateX) * scaleRatio;
      this.translateY = centerY - (centerY - this.translateY) * scaleRatio;
      this.scale = newScale;

      this.updateTransform();
      this.updateZoomIndicator();
    }

    reset() {
      this.scale = 1;
      this.translateX = 0;
      this.translateY = 0;
      this.updateTransform();
      this.updateZoomIndicator();
    }

    fitToView() {
      const containerRect = this.container.getBoundingClientRect();
      const svgRect = this.svg.getBoundingClientRect();

      // Reset first to get accurate SVG dimensions
      this.scale = 1;
      this.translateX = 0;
      this.translateY = 0;
      this.updateTransform();

      // Recalculate after reset
      const svgBBox = this.svg.getBBox ? this.svg.getBBox() : { width: svgRect.width, height: svgRect.height };

      // Calculate scale to fit
      const scaleX = (containerRect.width - 40) / svgBBox.width;
      const scaleY = (containerRect.height - 40) / svgBBox.height;
      this.scale = Math.min(scaleX, scaleY, 1); // Don't scale up, only down

      // Center the content
      const scaledWidth = svgBBox.width * this.scale;
      const scaledHeight = svgBBox.height * this.scale;
      this.translateX = (containerRect.width - scaledWidth) / 2;
      this.translateY = (containerRect.height - scaledHeight) / 2;

      this.updateTransform();
      this.updateZoomIndicator();
    }

    destroy() {
      // Remove event listeners would go here if needed
      // For LiveView, the container is removed automatically
    }
  }

  /**
   * LiveView Hook for Broadway Pipeline Zoom
   */
  const BroadwayPipelineZoom = {
    mounted() {
      this.initPanZoom();
    },

    updated() {
      // Preserve zoom state when SVG content changes
      if (this.controller) {
        const svg = this.el.querySelector('svg');
        if (svg && svg !== this.controller.svg) {
          // Save current zoom state
          const savedScale = this.controller.scale;
          const savedTranslateX = this.controller.translateX;
          const savedTranslateY = this.controller.translateY;
          
          // Reinitialize with new SVG
          this.initPanZoom();
          
          // Restore zoom state
          if (this.controller) {
            this.controller.scale = savedScale;
            this.controller.translateX = savedTranslateX;
            this.controller.translateY = savedTranslateY;
            this.controller.updateTransform();
            this.controller.updateZoomIndicator();
          }
        }
      }
    },

    destroyed() {
      if (this.controller) {
        this.controller.destroy();
      }
    },

    initPanZoom() {
      const svg = this.el.querySelector('svg');
      if (!svg) {
        console.warn('BroadwayPipelineZoom: No SVG element found');
        return;
      }

      // Set up container styles
      this.el.style.overflow = 'hidden';
      this.el.style.cursor = 'grab';
      this.el.style.position = 'relative';

      // Create controller
      this.controller = new PanZoomController(this.el, svg);

      // Set up control button event handlers
      this.setupControls();
    },

    setupControls() {
      const controls = this.el.querySelector('[data-panzoom-controls]');
      if (!controls) return;

      controls.querySelector('[data-zoom-in]')?.addEventListener('click', () => {
        this.controller.zoomIn();
      });

      controls.querySelector('[data-zoom-out]')?.addEventListener('click', () => {
        this.controller.zoomOut();
      });

      controls.querySelector('[data-zoom-reset]')?.addEventListener('click', () => {
        this.controller.reset();
      });

      controls.querySelector('[data-zoom-fit]')?.addEventListener('click', () => {
        this.controller.fitToView();
      });
    }
  };

  // Export for different module systems
  const BroadwayDashboardHooks = {
    BroadwayPipelineZoom
  };

  // AMD
  if (typeof define === 'function' && define.amd) {
    define(function() { return BroadwayDashboardHooks; });
  }
  // CommonJS
  else if (typeof module !== 'undefined' && module.exports) {
    module.exports = BroadwayDashboardHooks;
  }
  // Browser global
  else {
    window.BroadwayDashboardHooks = BroadwayDashboardHooks;

    // Also register with LiveDashboard if available
    if (window.LiveDashboard && typeof window.LiveDashboard.registerCustomHooks === 'function') {
      window.LiveDashboard.registerCustomHooks(BroadwayDashboardHooks);
    }
  }
})();
