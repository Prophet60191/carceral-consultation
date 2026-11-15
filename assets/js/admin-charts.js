import {
  Chart,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
  Title,
  Tooltip,
  Legend,
  LineController,
  Filler
} from 'chart.js';
import { themeColor } from './theme.js';
import 'chartjs-adapter-moment';

// Register Chart.js components
Chart.register(
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
  Title,
  Tooltip,
  Legend,
  LineController,
  Filler
);

export class AdminCharts {
  constructor() {
    this.charts = {};
    this.defaultOptions = {
      responsive: true,
      maintainAspectRatio: false,
      interaction: {
        intersect: false,
        mode: 'index'
      },
      plugins: {
        legend: {
          display: true,
          position: 'top',
          labels: {
            usePointStyle: true,
            padding: 20,
            font: {
              size: 12,
              family: 'Inter, system-ui, sans-serif'
            },
            color: themeColor("base-content")
          }
        },
        tooltip: {
          enabled: true,
          backgroundColor: themeColor("base-300"),
          titleColor: themeColor("base-content"),
          bodyColor: themeColor("base-content"),
          borderColor: themeColor("line"),
          borderWidth: 1,
          cornerRadius: 8,
          displayColors: false,
          padding: 12,
          titleFont: {
            size: 14,
            weight: 'bold'
          },
          bodyFont: {
            size: 13
          }
        }
      },
      scales: {
        x: {
          display: true,
          grid: {
            display: false
          },
          ticks: {
            color: themeColor("muted"),
            font: {
              size: 11
            }
          }
        },
        y: {
          display: true,
          grid: {
            color: themeColor("line"),
            drawBorder: false
          },
          ticks: {
            color: themeColor("muted"),
            font: {
              size: 11
            },
            callback: function(value) {
              return Number.isInteger(value) ? value : '';
            }
          }
        }
      },
      elements: {
        line: {
          tension: 0.4,
          borderWidth: 3,
          fill: true
        },
        point: {
          radius: 0,
          hoverRadius: 6,
          hoverBorderWidth: 2,
          hoverBorderColor: themeColor("base-content")
        }
      },
      animation: {
        duration: 800,
        easing: 'easeInOutQuart'
      }
    };
  }

  createUsersChart(canvasId, data) {
    const ctx = document.getElementById(canvasId);
    if (!ctx) return null;

    const chartData = {
      labels: data.labels,
      datasets: [{
        label: 'Users',
        data: data.values,
        borderColor: themeColor("chart-1"),
        backgroundColor: themeColor("chart-1", 0.1),
        pointBackgroundColor: themeColor("chart-1"),
        pointBorderColor: themeColor("base-content"),
        pointHoverBackgroundColor: themeColor("chart-1"),
        pointHoverBorderColor: themeColor("base-content"),
      }]
    };

    if (this.charts[canvasId]) {
      this.charts[canvasId].destroy();
    }

    this.charts[canvasId] = new Chart(ctx, {
      type: 'line',
      data: chartData,
      options: this.defaultOptions
    });

    return this.charts[canvasId];
  }

  createEventsChart(canvasId, data) {
    const ctx = document.getElementById(canvasId);
    if (!ctx) return null;

    const chartData = {
      labels: data.labels,
      datasets: [{
        label: 'Events',
        data: data.values,
        borderColor: themeColor("chart-2"),
        backgroundColor: themeColor("chart-2", 0.1),
        pointBackgroundColor: themeColor("chart-2"),
        pointBorderColor: themeColor("base-content"),
        pointHoverBackgroundColor: themeColor("chart-2"),
        pointHoverBorderColor: themeColor("base-content"),
      }]
    };

    if (this.charts[canvasId]) {
      this.charts[canvasId].destroy();
    }

    this.charts[canvasId] = new Chart(ctx, {
      type: 'line',
      data: chartData,
      options: this.defaultOptions
    });

    return this.charts[canvasId];
  }

  updateChart(canvasId, data) {
    const chart = this.charts[canvasId];
    if (!chart) return;

    chart.data.labels = data.labels;
    chart.data.datasets[0].data = data.values;
    chart.update('active');
  }

  destroyChart(canvasId) {
    if (this.charts[canvasId]) {
      this.charts[canvasId].destroy();
      delete this.charts[canvasId];
    }
  }

  destroyAllCharts() {
    Object.keys(this.charts).forEach(canvasId => {
      this.destroyChart(canvasId);
    });
  }
}

// Create global instance
window.AdminCharts = new AdminCharts();