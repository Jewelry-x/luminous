import { Chart, registerables, Tooltip } from 'chart.js'
import { DateTime } from 'luxon'
import "chartjs-adapter-luxon"
import zoomPlugin from 'chartjs-plugin-zoom';

let colors = ["#fd7f6f", "#7eb0d5", "#b2e061", "#bd7ebe", "#ffb55a", "#ffee65", "#beb9db", "#fdcce5", "#8bd3c7"]

// The following defines a new option to use as tooltip position
// see: config.options.plugins.tooltip.position
// for more: https://www.chartjs.org/docs/latest/configuration/tooltip.html#custom-position-modes
Tooltip.positioners.cursor = function (elements, eventPosition) {
  return eventPosition
}

Chart.register(zoomPlugin)

Chart.register({
  id: 'nodata',
  afterDraw: function (chart, args, options) {
    if (chart.data.datasets.length === 0) {
      chart.ctx.save();
      chart.ctx.textAlign = 'center';
      chart.ctx.textBaseline = 'middle';
      chart.ctx.font = "22px Arial";
      chart.ctx.fillStyle = "gray";
      chart.ctx.fillText('No data available', chart.chartArea.width / 2, chart.chartArea.height / 2);
      chart.ctx.restore();
    }

    // draw a vertical line at cursor
    if (chart.tooltip?._active?.length) {
      let x = chart.tooltip._active[0].element.x;
      let yAxis = chart.scales.y;
      let ctx = chart.ctx;
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(x, yAxis.top);
      ctx.lineTo(x, yAxis.bottom);
      ctx.lineWidth = 1;
      ctx.strokeStyle = 'rgba(0, 0, 0, 0.4)';
      ctx.stroke();
      ctx.restore();
    }
  }
})

function ChartJSHook() {
  this.mounted = function () {
    Chart.register(...registerables);

    // chart configuration
    let config = {
      type: 'line',
      data: {
        datasets: []
      },
      options: {
        animation: false,
        interaction: {
          mode: 'x'
        },
        scales: {
          x: {
            type: "time",
            grid: {
              display: false
            },
            time: {
              minUnit: 'hour',
              tooltipFormat: "yyyy-MM-dd HH:mm",
              displayFormats: {
                hour: 'HH:mm',
                day: 'MMM dd'
              }
            },
            ticks: {
              source: 'data',
              major: {
                enabled: true
              },
              // Automatically adjusts the number of the ticks by increasing the padding between them,
              // when autoSkip is enabled (it is by default)
              autoSkipPadding: 10,
              font: {
                size: 12
              }
            },
            adapters: {
              date: {
                setZone: true
              }
            }
          },
          y: {
            title: {
              font: {
                size: 16
              }
            },
            ticks: {
              font: {
                size: 14
              }
            },
            grid: {
              display: true
            }
          }
        },
        plugins: {
          tooltip: {
            position: 'cursor',
            intersect: false,
            callbacks: {
              label: function (context) {
                let label = context.dataset.label || ''

                if (label) {
                  label += ': '
                }
                if (context.parsed.y !== null) {
                  label += context.parsed.y + " " + context.dataset.unit
                }
                return label
              }
            }
          }
        }
      }
    }

    let canvas = document.getElementById(this.el.id)
    let ctx = canvas.getContext("2d")

    // configure zoom functionality
    let time_range_selector_id = canvas.getAttribute("time-range-selector-id")
    if (time_range_selector_id !== null) {
      config.options.plugins.zoom = {
        zoom: {
          wheel: {
            enabled: false
          },
          pinch: {
            enabled: true
          },
          drag: {
            enabled: true
          },
          mode: 'x',
          onZoomComplete: function (chart) {
            if (chart.chart.triggerZoomCallbacks) {
              ticks = chart.chart.scales.x.ticks
              // zoom only there is at least 1 tick inside user selected area
              if (ticks.length > 0) {
                let from = DateTime.fromMillis(ticks[0].value).toFormat("yyyy-MM-dd'T'HH:mm:ssZZ")
                // We add one hour because we want the last tick of the selected area
                // to be included in the result
                let to = DateTime.fromMillis(ticks[ticks.length - 1].value)
                  .plus({ hours: 1 })
                  .toFormat("yyyy-MM-dd'T'HH:mm:ssZZ")
                let e = new CustomEvent('zoomCompleted', { detail: { from: from, to: to } })
                document.getElementById(time_range_selector_id).dispatchEvent(e)
              }

              // The zoom level has to be reset even in the case that the user
              // doesn't select any ticks. Otherwise, an exception is raised and
              // the chart stops working as expected.
              chart.chart.triggerZoomCallbacks = false
              chart.chart.resetZoom()
              chart.chart.triggerZoomCallbacks = true
            }
          }
        }
      }
    }

    // create the chart
    this.chart = new Chart(ctx, config)
    // we use this flag to prevent the infinite callback loop
    // when we call resetZoom() on the chart
    this.chart.triggerZoomCallbacks = true
    // setup the data refresh event handler (LV)
    this.handleEvent(this.el.id + "::refresh-data", this.handler())
    // setup the download CSV event handler
    canvas.addEventListener("panel:" + this.el.id + ":download:csv", this.downloadCSV())
    // setup the download PNG event handler
    canvas.addEventListener("panel:" + this.el.id + ":download:png", this.downloadPNG())
  }

  // download the chart's data as CSV
  this.downloadCSV = function () {
    return (event) => {
      // determine column labels
      labels = this.chart.data.datasets.map((dataset) => {
        return '\"' + dataset.label + '\"'
      })
      // we will keep rows as a map
      // where keys are unix timestamps
      // and values are arrays of a fixed size (number of datasets)
      // js maps preserve their order, so we then just need to
      // iterate over all (key, values) pairs and generate the csv
      rows = new Map()
      n = this.chart.data.datasets.length
      this.chart.data.datasets.forEach((dataset, idx) => {
        dataset.data.forEach((row) => {
          // what happens with time points that exist in one dataset but not in another?
          // this is why values have a fixed size (number of datasets)
          // and we set the value explicitly based on the current dataset's index
          values = rows.get(row.x) || Array(n).fill('')
          values[idx] = row.y
          rows.set(row.x, values)
        })
      })
      // the first row is for excel to automatically recognize the field separator
      csvRows = ['sep=,', '\"time\",' + labels.join(',')]
      rows.forEach((values, time) => {
        row = DateTime.fromMillis(time).toFormat("yyyy/MM/dd'T'HH:mm:ssZZZ")
        csvRows.push(row + ',' + values.join(','))
      })
      csv = csvRows.join('\r\n')

      var blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
      var url = URL.createObjectURL(blob);
      sendFileToClient(url, this.el.id + ".csv")
    }
  }

  // download the canvas as a png image
  this.downloadPNG = function () {
    return (event) => {
      url = this.el.toDataURL('image/png')
      sendFileToClient(url, this.el.id + ".png")
    }
  }

  this.handler = function () {
    return (payload) => {
      n = payload.datasets.length
      datasets = payload.datasets.map(function (dataset, idx) {
        return {
          label: dataset.label,
          unit: dataset.attrs.unit,
          borderColor: colors[idx % n] + "FF", // full opaque
          backgroundColor: colors[idx % n] + '40', // 1/4 opaque
          borderWidth: 1,
          pointRadius: 1,
          fill: dataset.attrs.fill ? 'origin' : false,
          type: dataset.attrs.type,
          data: dataset.rows
        }
      })
      this.chart.data = { datasets: datasets }

      // set time zone
      this.chart.options.scales.x.adapters.date.zone = payload.time_zone

      // display ylabel
      this.chart.options.scales.y.title.display = true
      this.chart.options.scales.y.title.text = payload.ylabel

      // toggle stacking
      this.chart.options.scales.y.stacked = payload.stacked_x
      this.chart.options.scales.x.stacked = payload.stacked_y

      // if we have no data, turn off some displays
      this.chart.options.scales.y.grid.display = (n > 0)
      this.chart.options.scales.y.display = (n > 0)
      this.chart.options.scales.x.display = (n > 0)

      this.chart.update()
    }
  }
}

function sendFileToClient(url, filename) {
  var link = document.createElement("a");
  link.setAttribute("href", url);
  link.setAttribute("download", filename);
  link.style.visibility = 'hidden';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}

export default ChartJSHook
