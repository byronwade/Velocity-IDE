import { Chart } from "./components/Chart";

export default function App() {
  return (
    <main className="page">
      <h1>Acme Dashboard</h1>
      <Chart metric="revenue" />
    </main>
  );
}
