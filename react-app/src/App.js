import './App.css';
import React, { useState, useEffect } from 'react';

/* const url = "https://udjs6zb81l.execute-api.eu-north-1.amazonaws.com/serverless_lambda_stage/weather_data";
 */
const url = process.env.REACT_APP_API_URL;

function App() {
  const [data, setData] = useState("")
  const fetchInfo = () => {
  return fetch(url + "/weather_data")
    .then((res) => res.json())
    .then((d) => setData(d.message))
  }

  useEffect(() => {
    fetchInfo();
  }, [])

  return (
    <div className="App">
      <p>using JavaScript inbuilt FETCH API</p>
      <p style={{ fontSize: 20 }}>{data}</p>
    </div>
  );
}

export default App;
