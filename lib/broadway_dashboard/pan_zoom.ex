defmodule BroadwayDashboard.PanZoom do
  @moduledoc false

  # Internal module that provides the JavaScript and CSS code for pan/zoom functionality.

  @doc """
  Returns the JavaScript code that implements pan/zoom functionality.
  This code self-initializes when the DOM is ready.
  """
  @spec javascript_code() :: String.t()
  def javascript_code do
    ~s"""
    (function() {
      "use strict";
      if (window.__broadwayPanZoomInitialized) return;
      window.__broadwayPanZoomInitialized = true;

      const DEFAULT_CONFIG = {
        minScale: 0.1,
        maxScale: 5,
        scaleStep: 0.1,
        wheelZoomSpeed: 0.001
      };

      class PanZoomController {
        constructor(container, svg, config) {
          this.container = container;
          this.svg = svg;
          this.config = Object.assign({}, DEFAULT_CONFIG, config || {});
          this.scale = 1;
          this.translateX = 0;
          this.translateY = 0;
          this.isDragging = false;
          this.isPinching = false;
          this.lastMouseX = 0;
          this.lastMouseY = 0;
          this.lastPinchDistance = 0;
          this.lastPinchCenter = null;
          this.updateTransform();
          this.bindEvents();
        }

        bindEvents() {
          var self = this;
          this.container.addEventListener('wheel', function(e) { self.handleWheel(e); }, { passive: false });
          this.container.addEventListener('mousedown', function(e) { self.handleMouseDown(e); });
          document.addEventListener('mousemove', function(e) { self.handleMouseMove(e); });
          document.addEventListener('mouseup', function(e) { self.handleMouseUp(e); });
          this.container.addEventListener('touchstart', function(e) { self.handleTouchStart(e); }, { passive: false });
          this.container.addEventListener('touchmove', function(e) { self.handleTouchMove(e); }, { passive: false });
          this.container.addEventListener('touchend', function(e) { self.handleTouchEnd(e); });
          this.container.addEventListener('contextmenu', function(e) { if (self.isDragging) e.preventDefault(); });
        }

        handleWheel(e) {
          e.preventDefault();
          var rect = this.container.getBoundingClientRect();
          var mouseX = e.clientX - rect.left;
          var mouseY = e.clientY - rect.top;
          var delta = -e.deltaY * this.config.wheelZoomSpeed;
          var newScale = Math.max(this.config.minScale, Math.min(this.config.maxScale, this.scale * (1 + delta)));
          if (newScale !== this.scale) {
            var scaleRatio = newScale / this.scale;
            this.translateX = mouseX - (mouseX - this.translateX) * scaleRatio;
            this.translateY = mouseY - (mouseY - this.translateY) * scaleRatio;
            this.scale = newScale;
            this.updateTransform();
            this.updateZoomIndicator();
          }
        }

        handleMouseDown(e) {
          if (e.button === 0) {
            this.isDragging = true;
            this.lastMouseX = e.clientX;
            this.lastMouseY = e.clientY;
            this.container.style.cursor = 'grabbing';
            e.preventDefault();
          }
        }

        handleMouseMove(e) {
          if (this.isDragging) {
            var dx = e.clientX - this.lastMouseX;
            var dy = e.clientY - this.lastMouseY;
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

        handleTouchStart(e) {
          if (e.touches.length === 1) {
            this.isDragging = true;
            this.lastMouseX = e.touches[0].clientX;
            this.lastMouseY = e.touches[0].clientY;
            e.preventDefault();
          } else if (e.touches.length === 2) {
            this.isPinching = true;
            this.isDragging = false;
            this.lastPinchDistance = this.getPinchDistance(e.touches);
            this.lastPinchCenter = this.getPinchCenter(e.touches);
            e.preventDefault();
          }
        }

        handleTouchMove(e) {
          if (this.isDragging && e.touches.length === 1) {
            var dx = e.touches[0].clientX - this.lastMouseX;
            var dy = e.touches[0].clientY - this.lastMouseY;
            this.translateX += dx;
            this.translateY += dy;
            this.lastMouseX = e.touches[0].clientX;
            this.lastMouseY = e.touches[0].clientY;
            this.updateTransform();
            e.preventDefault();
          } else if (this.isPinching && e.touches.length === 2) {
            var newDistance = this.getPinchDistance(e.touches);
            var newCenter = this.getPinchCenter(e.touches);
            var scaleChange = newDistance / this.lastPinchDistance;
            var newScale = Math.max(this.config.minScale, Math.min(this.config.maxScale, this.scale * scaleChange));
            if (newScale !== this.scale) {
              var rect = this.container.getBoundingClientRect();
              var centerX = newCenter.x - rect.left;
              var centerY = newCenter.y - rect.top;
              var scaleRatio = newScale / this.scale;
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
          var dx = touches[0].clientX - touches[1].clientX;
          var dy = touches[0].clientY - touches[1].clientY;
          return Math.sqrt(dx * dx + dy * dy);
        }

        getPinchCenter(touches) {
          return { x: (touches[0].clientX + touches[1].clientX) / 2, y: (touches[0].clientY + touches[1].clientY) / 2 };
        }

        updateTransform() {
          // Store transform in CSS custom properties on container so new SVGs inherit it
          this.container.style.setProperty('--pz-tx', this.translateX + 'px');
          this.container.style.setProperty('--pz-ty', this.translateY + 'px');
          this.container.style.setProperty('--pz-scale', this.scale);
        }

        updateZoomIndicator() {
          var indicator = this.container.querySelector('[data-zoom-level]');
          if (indicator) { indicator.textContent = Math.round(this.scale * 100) + '%'; }
        }

        zoomIn() {
          var rect = this.container.getBoundingClientRect();
          var centerX = rect.width / 2;
          var centerY = rect.height / 2;
          var newScale = Math.min(this.config.maxScale, this.scale * (1 + this.config.scaleStep));
          var scaleRatio = newScale / this.scale;
          this.translateX = centerX - (centerX - this.translateX) * scaleRatio;
          this.translateY = centerY - (centerY - this.translateY) * scaleRatio;
          this.scale = newScale;
          this.updateTransform();
          this.updateZoomIndicator();
        }

        zoomOut() {
          var rect = this.container.getBoundingClientRect();
          var centerX = rect.width / 2;
          var centerY = rect.height / 2;
          var newScale = Math.max(this.config.minScale, this.scale * (1 - this.config.scaleStep));
          var scaleRatio = newScale / this.scale;
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
          var containerRect = this.container.getBoundingClientRect();
          this.scale = 1;
          this.translateX = 0;
          this.translateY = 0;
          this.updateTransform();
          var svgBBox;
          if (this.svg && this.svg.getBBox) {
            try { svgBBox = this.svg.getBBox(); } catch(e) { svgBBox = null; }
          }
          if (!svgBBox || svgBBox.width === 0 || svgBBox.height === 0) {
            svgBBox = { width: containerRect.width, height: containerRect.height };
          }
          var scaleX = (containerRect.width - 40) / svgBBox.width;
          var scaleY = (containerRect.height - 40) / svgBBox.height;
          this.scale = Math.min(scaleX, scaleY, 1);
          var scaledWidth = svgBBox.width * this.scale;
          var scaledHeight = svgBBox.height * this.scale;
          this.translateX = (containerRect.width - scaledWidth) / 2;
          this.translateY = (containerRect.height - scaledHeight) / 2;
          this.updateTransform();
          this.updateZoomIndicator();
        }
      }

      function initPanZoom(container) {
        // Find the card-body that contains the SVG
        var cardBody = container.querySelector('.card-body');
        if (!cardBody) return;

        var svg = cardBody.querySelector('svg');
        if (!svg) return;

        // If controller already exists, just update the SVG reference and reapply transform
        if (container._panZoomController) {
          container._panZoomController.svg = svg;
          container._panZoomController.updateTransform();
          container._panZoomController.updateZoomIndicator();
          return;
        }

        container.style.overflow = 'hidden';
        container.style.cursor = 'grab';
        container.style.position = 'relative';

        // Apply transform directly to the SVG
        var controller = new PanZoomController(container, svg);
        container._panZoomController = controller;

        var controls = container.querySelector('[data-panzoom-controls]');
        if (controls && !controls._bindingsAttached) {
          controls._bindingsAttached = true;
          var zoomIn = controls.querySelector('[data-zoom-in]');
          var zoomOut = controls.querySelector('[data-zoom-out]');
          var zoomReset = controls.querySelector('[data-zoom-reset]');
          var zoomFit = controls.querySelector('[data-zoom-fit]');
          if (zoomIn) zoomIn.addEventListener('click', function() { container._panZoomController.zoomIn(); });
          if (zoomOut) zoomOut.addEventListener('click', function() { container._panZoomController.zoomOut(); });
          if (zoomReset) zoomReset.addEventListener('click', function() { container._panZoomController.reset(); });
          if (zoomFit) zoomFit.addEventListener('click', function() { container._panZoomController.fitToView(); });
        }
      }

      function initAll() {
        var containers = document.querySelectorAll('.broadway-pipeline-zoom-container');
        containers.forEach(function(container) { initPanZoom(container); });
      }

      // Set up MutationObserver when body is available
      function setupObserver() {
        if (!document.body) {
          // Body not ready yet, wait for DOMContentLoaded
          document.addEventListener('DOMContentLoaded', setupObserver);
          return;
        }

        // Re-initialize on LiveView page updates using MutationObserver
        var pendingUpdate = false;
        var observer = new MutationObserver(function(mutations) {
          var dominated = mutations.some(function(mutation) {
            return mutation.type === 'childList' && mutation.addedNodes.length > 0;
          });
          if (dominated && !pendingUpdate) {
            pendingUpdate = true;
            requestAnimationFrame(function() {
              initAll();
              pendingUpdate = false;
            });
          }
        });
        observer.observe(document.body, { childList: true, subtree: true });

        // Also initialize immediately if containers already exist
        initAll();
      }

      // Initialize when DOM is ready
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', setupObserver);
      } else {
        setupObserver();
      }

      // Export for hook-based usage
      window.BroadwayDashboardHooks = {
        BroadwayPipelineZoom: {
          mounted: function() { initPanZoom(this.el); },
          updated: function() {
            if (!this.el._panZoomController) { initPanZoom(this.el); }
          }
        }
      };
    })();
    """
  end

  @doc """
  Returns the CSS code for pan/zoom styling.
  """
  @spec css_code() :: String.t()
  def css_code do
    ~s"""
    .broadway-pipeline-zoom-container {
      position: relative;
      overflow: hidden;
      cursor: grab;
      min-height: 200px;
    }
    .broadway-pipeline-zoom-container .card-body svg {
      will-change: transform;
      transform: translate(var(--pz-tx, 0px), var(--pz-ty, 0px)) scale(var(--pz-scale, 1));
      transform-origin: 0 0;
    }
    .broadway-pipeline-zoom-container:active {
      cursor: grabbing;
    }
    .broadway-pipeline-zoom-controls {
      position: absolute;
      top: 8px;
      right: 8px;
      display: flex;
      gap: 4px;
      z-index: 10;
      background: rgba(255, 255, 255, 0.95);
      border-radius: 4px;
      padding: 4px;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
    }
    .broadway-pipeline-zoom-controls button {
      width: 28px;
      height: 28px;
      border: 1px solid #ddd;
      background: white;
      border-radius: 4px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 14px;
      color: #333;
      transition: background-color 0.15s, border-color 0.15s;
    }
    .broadway-pipeline-zoom-controls button:hover {
      background: #f5f5f5;
      border-color: #ccc;
    }
    .broadway-pipeline-zoom-controls button:active {
      background: #e5e5e5;
    }
    .broadway-pipeline-zoom-level {
      display: flex;
      align-items: center;
      padding: 0 8px;
      font-size: 12px;
      color: #666;
      min-width: 45px;
      justify-content: center;
    }
    .broadway-pipeline-zoom-hint {
      position: absolute;
      bottom: 8px;
      left: 8px;
      font-size: 11px;
      color: #999;
      background: rgba(255, 255, 255, 0.8);
      padding: 2px 6px;
      border-radius: 3px;
    }
    """
  end
end
