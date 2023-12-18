import './App.css';
import React from 'react';
import asciichart from 'asciichart';

const url = process.env.REACT_APP_API_URL;

class DynamicGraph extends React.Component {
  constructor(props) {
    super(props);
    this.state = {temperature_data: [0], humidity_data:[0]};
  }

  tick() {
    var fetch_url = url + "/weather_data"
    var lastTimestamp = this.state.lastTimestamp;
    if (lastTimestamp) {fetch_url += "?gt=" + lastTimestamp;}

    fetch(fetch_url)
      .then((res) => res.json())
      .then((d) => {
          var temperatures = d.temperatures.map(Number);
          var humidities = d.humidities.map(Number);
          var timestamps = d.timestamps;

          this.setState(state => ({
             temperature_data: state.temperature_data.concat(temperatures),
             temperature_graph: asciichart.plot(state.temperature_data),
             humidity_data: state.humidity_data.concat(humidities),
             humidity_graph: asciichart.plot(state.humidity_data),
             lastTimestamp: timestamps[timestamps.length - 1] || lastTimestamp,
          }));
      });
  }

  componentDidMount() {
    this.interval = setInterval(() => this.tick(), 5000);
  }

  componentWillUnmount() {
    clearInterval(this.interval);
  }

  render() {
    return (
      <>
      <p>Temperature:</p>
      <pre><code>
        {this.state.temperature_graph}
      </code></pre>
      <p>Humidity:</p>
      <pre><code>
        {this.state.humidity_graph}
      </code></pre>
      </>
    );
  }
}

function App() {
  return (
    <div className="App">
      <DynamicGraph/>
    </div>
  );
}

export default App;
