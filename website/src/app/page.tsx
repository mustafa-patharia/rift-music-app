import { Nav, Scrubber, Footer } from "@/components/Chrome";
import {
  Hero, ProofBand, Statement, ProductShot, Features,
  Notch, Native, Compare, Faq, Install,
} from "@/components/Sections";
import Together from "@/components/Together";
import SoundField from "@/components/SoundField";

export default function Page() {
  return (
    <>
      <div className="aurora" aria-hidden>
        <SoundField />
      </div>

      <Nav />
      <Scrubber />

      <main>
        <Hero />
        <ProofBand />
        <Statement />
        <ProductShot />
        <Features />
        <Together />
        <hr className="fault rail" />
        <Notch />
        <Native />
        <Compare />
        <Faq />
        <Install />
      </main>

      <Footer />
    </>
  );
}
