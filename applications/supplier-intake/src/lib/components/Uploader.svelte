<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import '@uppy/core/css/style.min.css';
  import '@uppy/dashboard/css/style.min.css';
  let target: HTMLDivElement;
  let failure = $state('');
  onMount(() => {
    let disposed = false;
    let cleanup = () => {};
    void (async () => {
      try {
        const [{ default: Uppy }, { default: Dashboard }, { default: XHRUpload }] =
          await Promise.all([
            import('@uppy/core'),
            import('@uppy/dashboard'),
            import('@uppy/xhr-upload'),
          ]);
        if (disposed) return;
        const uppy = new Uppy({
          restrictions: {
            maxNumberOfFiles: 1,
            maxFileSize: 512 * 1024,
            allowedFileTypes: ['.csv', '.xlsx'],
          },
        });
        cleanup = () => uppy.destroy();
        uppy
          .use(Dashboard, {
            target,
            inline: true,
            height: 280,
            width: '100%',
            note: 'CSV or XLSX · 512 KiB · 100 rows · one worksheet',
          })
          .use(XHRUpload, {
            endpoint: '/api/upload',
            fieldName: 'file',
            formData: true,
            allowedMetaFields: [],
          });
        uppy.on('upload-success', (_file, response) => {
          const body = response.body as { id?: string };
          if (body.id) void goto(`/batches/${body.id}`);
        });
        uppy.on('upload-error', (_file, error, response) => {
          failure = (response?.body as { error?: string })?.error ?? error.message;
        });
      } catch {
        cleanup();
        failure = 'The uploader could not be loaded. Reload the page to try again.';
      }
    })();
    return () => {
      disposed = true;
      cleanup();
    };
  });
</script>

<div bind:this={target}></div>
{#if failure}<p role="alert" class="error">{failure}</p>{/if}
