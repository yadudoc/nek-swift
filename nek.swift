import "apps";

(int retcode) sweep (string prefix, file json, file tusr, string pname, float[] pvals, int nwrite, boolean legacy, int nstep, int io_step, int step_block, int foo, int nodes, int mode){

retcode = 1;

foreach pval,i in pvals {

  /* Pick a directory to run in */
  string tdir = sprintf("./%s_%s_%f", prefix, pname, pval);
  string name = sprintf("./%s_%s_%f", prefix, pname, pval);
  file tdir_f  <single_file_mapper; file=strcat("/projects/alpha-nek/nek-swift/",tdir)>;
  //(tdir_f) = mkdir(tdir);

  /* Construct input files and build the nek5000 executable */
  file base     <single_file_mapper; file=sprintf("%s/%s.json", tdir, name)>;
  file rea      <single_file_mapper; file=sprintf("%s/%s.rea",  tdir, name)>;
  file map      <single_file_mapper; file=sprintf("%s/%s.map",  tdir, name)>;
  file usr      <single_file_mapper; file=sprintf("%s/%s.usr",  tdir, name)>;
  //file size_mod <single_file_mapper; file=sprintf("%s/SIZE",  tdir, name)>;
  file size_mod <single_file_mapper; file=sprintf("%s/size_mod.F90",  tdir)>;

  (usr, rea, map, base, size_mod) = genrun (json, tusr, name, tdir_f, pname, pval, _legacy=legacy);
  
  file nek5000 <single_file_mapper; file=sprintf("%s/nek5000", tdir, name)>;
  (nek5000) = makenek(tdir_f, "/home/maxhutch/nek/", name, usr, size_mod, _legacy=legacy);

  int[] iout; iout[0] = 1;
  int[] istep; istep[0] = 0;

  string[][] outfile_names_j;
  string[][] checkpoint_names_j;
  file[][] outfiles_j;
  file[][] checkpoints_j;

  iterate j {
    /* Configure the next iteration */
    string name_j = sprintf("./%s_%s_%f-%d", prefix, pname, pval, j);
    file config     <single_file_mapper; file=sprintf("%s/%s-%d.json", tdir, name, j)>;
    file rea_j      <single_file_mapper; file=sprintf("%s/%s-%d.rea",  tdir, name, j)>;
    file map_j      <single_file_mapper; file=sprintf("%s/%s-%d.map",  tdir, name, j)>;

    float iout_l; int istart;
    if (iout[j] < 2) {
      iout_l = 0.0;
      istart = 1;
    } else { 
      iout_l = toFloat(iout[j]);
      istart = iout[j] + 1;
    }

    (rea_j, map_j, config) = app_regen (base, tusr, name_j, tdir_f, "num_steps", toFloat(step_block), "restart",   iout_l);

    /* Run Nek! */
    file donek_o <single_file_mapper; file=sprintf("%s/%s-%d.output", tdir, name, j)>;
    file donek_e <single_file_mapper; file=sprintf("%s/%s-%d.error", tdir, name, j)>;
    string[] checkpoint_names, outfile_names;
    (checkpoint_names, outfile_names) = nek_out_names(tdir, name_j, istart, iout[j] + foo, nwrite);
    outfile_names_j[j] = outfile_names;
    checkpoint_names_j[j] = checkpoint_names;
    file[] outfiles <array_mapper; files=outfile_names>;
    file[] checkpoints <array_mapper; files=checkpoint_names>;
    outfiles_j[j] = outfiles;
    checkpoints_j[j] = checkpoints;


    if (j == 0){
      (donek_o, donek_e, outfiles, checkpoints) = app_donek(rea_j, map_j, tdir_f, name_j, nek5000, nodes, mode);
    } else {
      string[] new_checkpoints, new_outputs;
      (new_checkpoints, new_outputs) = nek_out_names(tdir, sprintf("./%s_%s_%f-%d", prefix, pname, pval, j), istart-2, istart-1, nwrite);
      
      file[] checks_new <array_mapper; files=new_checkpoints>;
      foreach f,ii in checkpoints_j[j-1]{
        checks_new[ii] = app_cp(f);
      }
      
      (donek_o, donek_e, outfiles, checkpoints) = app_donek_restart(rea_j, map_j, tdir_f, name_j, nek5000, checks_new, nodes, mode);
    }
 
    /* Analyze the outputs, making a bunch of pngs */
    file analyze_o <single_file_mapper; file=sprintf("%s/analyze-%d_out.txt", tdir, j)>;
    file analyze_e <single_file_mapper; file=sprintf("%s/analyze-%d_err.txt", tdir, j)>;
    file[] pngs <filesys_mapper; pattern=sprintf("%s/%s*.png", tdir, name_j)>;
    //file chest <single_file_mapper; file=sprintf("%s/%s-results", tdir, name_j)>;
    (analyze_o, analyze_e, pngs) = app_nek_analyze(config, outfiles, checkpoints, sprintf("%s/%s",tdir,name_j), istart, iout[j] + foo);
    

    /* Archive the outputs to HPSS  */
    file arch_o <single_file_mapper; file=sprintf("%s/arch-%d.output", tdir, j)>;
    file arch_e <single_file_mapper; file=sprintf("%s/arch-%d.error", tdir, j)>;
    (arch_o, arch_e) = app_archive(sprintf("%s/%s", tdir, name_j), outfiles, checkpoints, istart, iout[j] + foo);
 
    /* Publish the outputs to Petrel */
    file uplo_o <single_file_mapper; file=sprintf("%s/uplo-%d.output", tdir, j)>;
    file uplo_e <single_file_mapper; file=sprintf("%s/uplo-%d.error", tdir, j)>;
    (uplo_o, uplo_e) = app_upload(sprintf("%s/%s", tdir, name_j), config, pngs, istart, iout[j]+foo);

   istep[j+1] = istep[j] + step_block;
   iout[j+1] = iout[j] + foo;
  } until (istep[j] >= nstep); 
}

}
