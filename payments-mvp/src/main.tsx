import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';
import './styles.css';
import { PaymentsProvider } from './store/PaymentsStore';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <PaymentsProvider>
        <App />
      </PaymentsProvider>
    </BrowserRouter>
  </React.StrictMode>,
);
