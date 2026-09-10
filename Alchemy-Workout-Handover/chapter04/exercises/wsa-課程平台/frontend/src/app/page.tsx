import { redirect } from 'next/navigation'

export default function Home() {
  // Redirect to the default authenticated page
  // Worker should update this redirect target based on the flow-map
  redirect('/products')
}
